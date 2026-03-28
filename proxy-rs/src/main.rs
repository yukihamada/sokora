//! Anthropic Messages API → OpenAI Chat Completions proxy for MLX
//! Rust (axum) implementation for minimal latency overhead.

use axum::{
    body::Body,
    extract::State,
    http::{header, StatusCode},
    response::{IntoResponse, Response, Sse},
    routing::{get, post},
    Json, Router,
};
use futures::stream::{self, StreamExt};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::{collections::HashMap, env, sync::Arc, time::Duration};

// ── Configuration ──

struct AppState {
    client: Client,
    models: HashMap<String, Backend>,
    routes: HashMap<String, String>,
}

#[derive(Clone)]
struct Backend {
    mlx_model: String,
    port: u16,
    label: String,
}

fn default_config() -> (HashMap<String, Backend>, HashMap<String, String>) {
    let mut models = HashMap::new();
    models.insert(
        "main".into(),
        Backend {
            mlx_model: env::var("MLX_MODEL_MAIN")
                .unwrap_or_else(|_| "mlx-community/Qwen3.5-122B-A10B-4bit".into()),
            port: env::var("MLX_PORT_MAIN")
                .ok()
                .and_then(|p| p.parse().ok())
                .unwrap_or(5000),
            label: "122B".into(),
        },
    );
    models.insert(
        "fast".into(),
        Backend {
            mlx_model: env::var("MLX_MODEL_FAST")
                .unwrap_or_else(|_| "mlx-community/Qwen3.5-35B-A3B-4bit".into()),
            port: env::var("MLX_PORT_FAST")
                .ok()
                .and_then(|p| p.parse().ok())
                .unwrap_or(5001),
            label: "35B".into(),
        },
    );
    models.insert(
        "vision".into(),
        Backend {
            mlx_model: env::var("MLX_MODEL_VISION")
                .unwrap_or_else(|_| "mlx-community/Qwen3-VL-8B-Instruct-4bit".into()),
            port: env::var("MLX_PORT_VISION")
                .ok()
                .and_then(|p| p.parse().ok())
                .unwrap_or(5002),
            label: "VL-8B".into(),
        },
    );

    let mut routes = HashMap::new();
    for name in [
        "claude-sonnet-4-6",
        "claude-sonnet-4-6-20250514",
        "claude-opus-4-6",
        "claude-opus-4-6-20250514",
        "claude-3-5-sonnet-20241022",
        "claude-3-5-sonnet-latest",
    ] {
        routes.insert(name.into(), "main".into());
    }
    for name in ["claude-haiku-4-5-20251001", "claude-3-5-haiku-latest"] {
        routes.insert(name.into(), "fast".into());
    }

    (models, routes)
}

// ── Anthropic ↔ OpenAI types ──

#[derive(Deserialize)]
struct AnthropicRequest {
    model: Option<String>,
    messages: Vec<Value>,
    system: Option<Value>,
    max_tokens: Option<u32>,
    temperature: Option<f32>,
    stream: Option<bool>,
    tools: Option<Vec<Value>>,
}

#[derive(Serialize)]
struct AnthropicResponse {
    id: String,
    #[serde(rename = "type")]
    msg_type: String,
    role: String,
    model: String,
    content: Vec<Value>,
    stop_reason: Option<String>,
    stop_sequence: Option<String>,
    usage: Value,
}

// ── Conversion functions ──

fn has_images(messages: &[Value]) -> bool {
    messages.iter().any(|msg| {
        if let Some(content) = msg.get("content").and_then(|c| c.as_array()) {
            content.iter().any(|block| {
                matches!(
                    block.get("type").and_then(|t| t.as_str()),
                    Some("image" | "image_url")
                )
            })
        } else {
            false
        }
    })
}

fn convert_tools(tools: &[Value]) -> Vec<Value> {
    tools
        .iter()
        .map(|t| {
            json!({
                "type": "function",
                "function": {
                    "name": t.get("name").unwrap_or(&json!("")),
                    "description": t.get("description").unwrap_or(&json!("")),
                    "parameters": t.get("input_schema").unwrap_or(&json!({})),
                }
            })
        })
        .collect()
}

fn convert_messages(messages: &[Value], system: &Option<Value>) -> Vec<Value> {
    let mut oai = Vec::new();

    // System prompt
    if let Some(sys) = system {
        let text = if let Some(s) = sys.as_str() {
            s.to_string()
        } else if let Some(arr) = sys.as_array() {
            arr.iter()
                .filter_map(|b| {
                    if b.get("type").and_then(|t| t.as_str()) == Some("text") {
                        b.get("text").and_then(|t| t.as_str()).map(String::from)
                    } else {
                        None
                    }
                })
                .collect::<Vec<_>>()
                .join(" ")
        } else {
            String::new()
        };
        if !text.is_empty() {
            oai.push(json!({"role": "system", "content": text}));
        }
    }

    for msg in messages {
        let role = msg.get("role").and_then(|r| r.as_str()).unwrap_or("user");
        let content = msg.get("content");

        // String content
        if let Some(s) = content.and_then(|c| c.as_str()) {
            oai.push(json!({"role": role, "content": s}));
            continue;
        }

        // Array content
        if let Some(blocks) = content.and_then(|c| c.as_array()) {
            let mut text_parts = Vec::new();
            let mut image_parts: Vec<Value> = Vec::new();
            let mut tool_calls = Vec::new();
            let mut tool_results = Vec::new();

            for block in blocks {
                match block.get("type").and_then(|t| t.as_str()) {
                    Some("text") => {
                        if let Some(t) = block.get("text").and_then(|t| t.as_str()) {
                            text_parts.push(t.to_string());
                        }
                    }
                    Some("image") => {
                        if let Some(src) = block.get("source") {
                            if src.get("type").and_then(|t| t.as_str()) == Some("base64") {
                                let media = src
                                    .get("media_type")
                                    .and_then(|m| m.as_str())
                                    .unwrap_or("image/jpeg");
                                let data = src.get("data").and_then(|d| d.as_str()).unwrap_or("");
                                let url = format!("data:{media};base64,{data}");
                                image_parts.push(json!({"type": "image_url", "image_url": {"url": url}}));
                            }
                        }
                    }
                    Some("image_url") => {
                        image_parts.push(block.clone());
                    }
                    Some("tool_use") => {
                        tool_calls.push(json!({
                            "id": block.get("id").unwrap_or(&json!("")),
                            "type": "function",
                            "function": {
                                "name": block.get("name").unwrap_or(&json!("")),
                                "arguments": serde_json::to_string(
                                    block.get("input").unwrap_or(&json!({}))
                                ).unwrap_or_default(),
                            }
                        }));
                    }
                    Some("tool_result") => {
                        let tc = block.get("content");
                        let text = if let Some(s) = tc.and_then(|c| c.as_str()) {
                            s.to_string()
                        } else if let Some(arr) = tc.and_then(|c| c.as_array()) {
                            arr.iter()
                                .filter_map(|b| b.get("text").and_then(|t| t.as_str()))
                                .collect::<Vec<_>>()
                                .join("\n")
                        } else {
                            String::new()
                        };
                        tool_results.push(json!({
                            "role": "tool",
                            "tool_call_id": block.get("tool_use_id").unwrap_or(&json!("")),
                            "content": text,
                        }));
                    }
                    _ => {}
                }
            }

            if role == "assistant" {
                let mut m = json!({"role": "assistant", "content": text_parts.join("\n")});
                if !tool_calls.is_empty() {
                    m["tool_calls"] = json!(tool_calls);
                }
                oai.push(m);
            } else if role == "user" {
                if !image_parts.is_empty() {
                    let mut multi: Vec<Value> = image_parts;
                    if !text_parts.is_empty() {
                        multi.push(json!({"type": "text", "text": text_parts.join("\n")}));
                    }
                    oai.push(json!({"role": "user", "content": multi}));
                } else if !text_parts.is_empty() {
                    oai.push(json!({"role": "user", "content": text_parts.join("\n")}));
                }
                for tr in tool_results {
                    oai.push(tr);
                }
            }
        }
    }
    oai
}

fn oai_to_anthropic(data: &Value, model: &str) -> Value {
    let choice = &data["choices"][0];
    let message = &choice["message"];
    let usage = &data["usage"];

    let mut content = Vec::new();

    if let Some(text) = message.get("content").and_then(|c| c.as_str()) {
        if !text.is_empty() {
            content.push(json!({"type": "text", "text": text}));
        }
    }

    if let Some(tcs) = message.get("tool_calls").and_then(|t| t.as_array()) {
        for tc in tcs {
            let func = &tc["function"];
            let args: Value = serde_json::from_str(
                func.get("arguments").and_then(|a| a.as_str()).unwrap_or("{}"),
            )
            .unwrap_or(json!({}));
            content.push(json!({
                "type": "tool_use",
                "id": format!("toolu_{}", uuid::Uuid::new_v4().to_string().replace("-", "")[..24].to_string()),
                "name": func.get("name").unwrap_or(&json!("")),
                "input": args,
            }));
        }
    }

    if content.is_empty() {
        content.push(json!({"type": "text", "text": ""}));
    }

    let stop_reason = if choice
        .get("finish_reason")
        .and_then(|f| f.as_str())
        == Some("tool_calls")
    {
        "tool_use"
    } else {
        "end_turn"
    };

    json!({
        "id": format!("msg_{}", &uuid::Uuid::new_v4().to_string().replace("-", "")[..24]),
        "type": "message",
        "role": "assistant",
        "model": model,
        "content": content,
        "stop_reason": stop_reason,
        "stop_sequence": null,
        "usage": {
            "input_tokens": usage.get("prompt_tokens").unwrap_or(&json!(0)),
            "output_tokens": usage.get("completion_tokens").unwrap_or(&json!(0)),
            "cache_creation_input_tokens": 0,
            "cache_read_input_tokens": 0,
        }
    })
}

// ── Handlers ──

async fn handle_messages(
    State(state): State<Arc<AppState>>,
    Json(req): Json<AnthropicRequest>,
) -> Response {
    let model_name = req.model.as_deref().unwrap_or("claude-sonnet-4-6");
    let stream = req.stream.unwrap_or(false);

    // Route: images → vision, else by model name
    let backend_key = if has_images(&req.messages) {
        "vision".to_string()
    } else {
        state
            .routes
            .get(model_name)
            .cloned()
            .unwrap_or_else(|| "main".into())
    };
    let backend = state.models.get(&backend_key).unwrap();
    let mlx_url = format!("http://127.0.0.1:{}/v1/chat/completions", backend.port);

    eprintln!(
        "[{}] {} -> {} :{} stream={} tools={}",
        chrono_now(),
        model_name,
        backend.label,
        backend.port,
        stream,
        req.tools.as_ref().map_or(0, |t| t.len())
    );

    let mut oai_body = json!({
        "model": backend.mlx_model,
        "messages": convert_messages(&req.messages, &req.system),
        "max_tokens": req.max_tokens.unwrap_or(4096),
        "chat_template_kwargs": {"enable_thinking": false},
    });

    if let Some(temp) = req.temperature {
        oai_body["temperature"] = json!(temp);
    }
    if let Some(ref tools) = req.tools {
        oai_body["tools"] = json!(convert_tools(tools));
    }

    if stream {
        return handle_stream(&state.client, &mlx_url, oai_body, model_name).await;
    }

    // Non-streaming
    match state.client.post(&mlx_url).json(&oai_body).send().await {
        Ok(resp) => match resp.json::<Value>().await {
            Ok(data) => Json(oai_to_anthropic(&data, model_name)).into_response(),
            Err(e) => error_response(500, &format!("JSON parse error: {e}")),
        },
        Err(e) => error_response(502, &format!("MLX connection error: {e}")),
    }
}

async fn handle_stream(
    client: &Client,
    mlx_url: &str,
    mut oai_body: Value,
    model: &str,
) -> Response {
    oai_body["stream"] = json!(true);
    let msg_id = format!(
        "msg_{}",
        &uuid::Uuid::new_v4().to_string().replace("-", "")[..24]
    );

    let resp = match client.post(mlx_url).json(&oai_body).send().await {
        Ok(r) => r,
        Err(e) => return error_response(502, &format!("MLX error: {e}")),
    };

    let model = model.to_string();
    let body_stream = resp.bytes_stream();

    // Build SSE response manually for maximum speed
    let sse_stream = async_stream::stream! {
        // message_start
        yield Ok::<_, std::convert::Infallible>(format!(
            "event: message_start\ndata: {}\n\n",
            json!({
                "type": "message_start",
                "message": {
                    "id": msg_id, "type": "message", "role": "assistant",
                    "model": model, "content": [], "stop_reason": null, "stop_sequence": null,
                    "usage": {"input_tokens": 0, "output_tokens": 0,
                              "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0}
                }
            })
        ));

        let mut text_started = false;
        let mut has_tool_calls = false;
        let mut content_index: usize = 0;
        let mut buffer = String::new();

        tokio::pin!(body_stream);
        while let Some(chunk_result) = body_stream.next().await {
            let chunk = match chunk_result {
                Ok(c) => c,
                Err(_) => break,
            };
            buffer.push_str(&String::from_utf8_lossy(&chunk));

            while let Some(nl) = buffer.find('\n') {
                let line = buffer[..nl].trim().to_string();
                buffer = buffer[nl + 1..].to_string();

                if !line.starts_with("data: ") { continue; }
                let data_str = &line[6..];
                if data_str == "[DONE]" { continue; }

                let chunk: Value = match serde_json::from_str(data_str) {
                    Ok(v) => v,
                    Err(_) => continue,
                };

                let delta = &chunk["choices"][0]["delta"];

                // Text content
                if let Some(text) = delta.get("content").and_then(|c| c.as_str()) {
                    if !text.is_empty() {
                        if !text_started {
                            yield Ok(format!(
                                "event: content_block_start\ndata: {}\n\n",
                                json!({"type": "content_block_start", "index": content_index,
                                       "content_block": {"type": "text", "text": ""}})
                            ));
                            text_started = true;
                        }
                        yield Ok(format!(
                            "event: content_block_delta\ndata: {}\n\n",
                            json!({"type": "content_block_delta", "index": content_index,
                                   "delta": {"type": "text_delta", "text": text}})
                        ));
                    }
                }

                // Tool calls
                if let Some(tcs) = delta.get("tool_calls").and_then(|t| t.as_array()) {
                    for tc in tcs {
                        let func = &tc["function"];
                        if let Some(name) = func.get("name").and_then(|n| n.as_str()) {
                            if !name.is_empty() {
                                has_tool_calls = true;
                                if text_started {
                                    yield Ok(format!(
                                        "event: content_block_stop\ndata: {}\n\n",
                                        json!({"type": "content_block_stop", "index": content_index})
                                    ));
                                    content_index += 1;
                                    text_started = false;
                                }
                                let toolu_id = format!("toolu_{}", &uuid::Uuid::new_v4().to_string().replace("-", "")[..24]);
                                yield Ok(format!(
                                    "event: content_block_start\ndata: {}\n\n",
                                    json!({"type": "content_block_start", "index": content_index,
                                           "content_block": {"type": "tool_use", "id": toolu_id, "name": name, "input": {}}})
                                ));
                                content_index += 1;
                            }
                        }
                        if let Some(args) = func.get("arguments").and_then(|a| a.as_str()) {
                            if !args.is_empty() {
                                yield Ok(format!(
                                    "event: content_block_delta\ndata: {}\n\n",
                                    json!({"type": "content_block_delta", "index": content_index - 1,
                                           "delta": {"type": "input_json_delta", "partial_json": args}})
                                ));
                            }
                        }
                    }
                }
            }
        }

        // Close open blocks
        if text_started {
            yield Ok(format!(
                "event: content_block_stop\ndata: {}\n\n",
                json!({"type": "content_block_stop", "index": 0})
            ));
        }
        if has_tool_calls {
            yield Ok(format!(
                "event: content_block_stop\ndata: {}\n\n",
                json!({"type": "content_block_stop", "index": content_index - 1})
            ));
        }

        let stop_reason = if has_tool_calls { "tool_use" } else { "end_turn" };
        yield Ok(format!(
            "event: message_delta\ndata: {}\n\n",
            json!({"type": "message_delta",
                   "delta": {"stop_reason": stop_reason, "stop_sequence": null},
                   "usage": {"output_tokens": 0}})
        ));
        yield Ok(format!(
            "event: message_stop\ndata: {}\n\n",
            json!({"type": "message_stop"})
        ));
    };

    Response::builder()
        .header(header::CONTENT_TYPE, "text/event-stream")
        .header(header::CACHE_CONTROL, "no-cache")
        .body(Body::from_stream(sse_stream))
        .unwrap()
}

async fn handle_count_tokens(Json(req): Json<Value>) -> Json<Value> {
    let msgs = convert_messages(
        req.get("messages")
            .and_then(|m| m.as_array())
            .unwrap_or(&vec![]),
        &req.get("system").cloned(),
    );
    let total: usize = msgs
        .iter()
        .map(|m| {
            m.get("content")
                .and_then(|c| c.as_str())
                .unwrap_or("")
                .len()
                / 4
        })
        .sum();
    Json(json!({"input_tokens": total}))
}

async fn handle_models(State(state): State<Arc<AppState>>) -> Json<Value> {
    let models: Vec<Value> = state
        .routes
        .keys()
        .map(|name| {
            json!({"id": name, "object": "model", "created": 1677610602, "owned_by": "anthropic"})
        })
        .collect();
    Json(json!({"data": models, "object": "list"}))
}

async fn handle_health() -> &'static str {
    "ok"
}

async fn catch_all(req: axum::http::Request<Body>) -> impl IntoResponse {
    eprintln!("[{}] CATCH-ALL {} {}", chrono_now(), req.method(), req.uri());
    Json(json!({"ok": true}))
}

fn error_response(status: u16, msg: &str) -> Response {
    let code = StatusCode::from_u16(status).unwrap_or(StatusCode::INTERNAL_SERVER_ERROR);
    (code, Json(json!({"error": {"message": msg}}))).into_response()
}

fn chrono_now() -> String {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs();
    let h = (now % 86400) / 3600;
    let m = (now % 3600) / 60;
    let s = now % 60;
    // JST = UTC + 9
    format!("{:02}:{:02}:{:02}", (h + 9) % 24, m, s)
}

#[tokio::main]
async fn main() {
    let (models, routes) = default_config();

    eprintln!("=== Anthropic Proxy (Rust/axum) ===");
    for (key, backend) in &models {
        eprintln!("  [{key}] {} -> :{} ({})", backend.mlx_model, backend.port, backend.label);
    }

    let client = Client::builder()
        .pool_max_idle_per_host(20)
        .pool_idle_timeout(Duration::from_secs(300))
        .tcp_keepalive(Duration::from_secs(60))
        .timeout(Duration::from_secs(300))
        .build()
        .unwrap();

    let state = Arc::new(AppState {
        client,
        models,
        routes,
    });

    let app = Router::new()
        .route("/v1/messages", post(handle_messages))
        .route("/v1/messages/count_tokens", post(handle_count_tokens))
        .route("/v1/models", get(handle_models))
        .route("/health", get(handle_health))
        .fallback(catch_all)
        .with_state(state);

    let port: u16 = env::var("PROXY_PORT")
        .ok()
        .and_then(|p| p.parse().ok())
        .unwrap_or(4001);

    let listener = tokio::net::TcpListener::bind(format!("0.0.0.0:{port}"))
        .await
        .unwrap();
    eprintln!("Listening on :{port}");
    axum::serve(listener, app).await.unwrap();
}
