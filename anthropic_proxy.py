"""Anthropic Messages API -> OpenAI Chat Completions proxy for MLX
Supports: text, streaming, tool_use/tool_result, multi-model routing"""
import json, uuid, time, os
from aiohttp import web, ClientSession

# ── Multi-model configuration ──
# Each MLX server runs on its own port. The proxy routes based on the
# Anthropic model name that Claude Code sends.
#
# Add models by:
#   1. Adding an entry to MODELS below
#   2. Starting an MLX server on the specified port
#   3. (Optional) map additional Anthropic names in MODEL_ROUTES

MODELS = {
    "main": {
        "mlx_model": os.environ.get("MLX_MODEL_MAIN", "mlx-community/Qwen3.5-122B-A10B-4bit"),
        "port": int(os.environ.get("MLX_PORT_MAIN", "5000")),
        "label": "Qwen3.5-122B (general)",
    },
    "fast": {
        "mlx_model": os.environ.get("MLX_MODEL_FAST", "mlx-community/Qwen3.5-35B-A3B-4bit"),
        "port": int(os.environ.get("MLX_PORT_FAST", "5001")),
        "label": "Qwen3.5-35B-A3B (fast)",
    },
    "vision": {
        "mlx_model": os.environ.get("MLX_MODEL_VISION", "mlx-community/Qwen3-VL-8B-Instruct-4bit"),
        "port": int(os.environ.get("MLX_PORT_VISION", "5002")),
        "label": "Qwen3-VL-8B (vision)",
    },
}

# Map Anthropic model names -> which backend to use
MODEL_ROUTES = {
    # Sonnet/Opus -> main (122B)
    "claude-sonnet-4-6":          "main",
    "claude-sonnet-4-6-20250514": "main",
    "claude-opus-4-6":            "main",
    "claude-opus-4-6-20250514":   "main",
    "claude-3-5-sonnet-20241022": "main",
    "claude-3-5-sonnet-latest":   "main",
    # Haiku -> fast (35B)
    "claude-haiku-4-5-20251001":  "fast",
    "claude-3-5-haiku-latest":    "fast",
}

DEFAULT_BACKEND = "main"

def has_images(messages):
    """Check if any message contains image content"""
    for msg in messages:
        content = msg.get("content", "")
        if isinstance(content, list):
            for block in content:
                if block.get("type") in ("image", "image_url"):
                    return True
                if block.get("type") == "source" and block.get("media_type", "").startswith("image/"):
                    return True
    return False

def get_backend(anthropic_model, messages=None):
    """Resolve Anthropic model name to MLX backend config.
    Auto-routes to vision backend if images are detected."""
    if messages and has_images(messages):
        return MODELS.get("vision", MODELS["main"])
    key = MODEL_ROUTES.get(anthropic_model, DEFAULT_BACKEND)
    backend = MODELS.get(key, MODELS["main"])
    return backend

def log(msg):
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)

# ── Anthropic → OpenAI conversion ──

def convert_tools(anthropic_tools):
    """Anthropic tools → OpenAI tools"""
    if not anthropic_tools:
        return None
    oai_tools = []
    for t in anthropic_tools:
        oai_tools.append({
            "type": "function",
            "function": {
                "name": t["name"],
                "description": t.get("description", ""),
                "parameters": t.get("input_schema", {}),
            }
        })
    return oai_tools

def convert_messages(messages, system=""):
    """Anthropic messages → OpenAI messages"""
    oai = []
    if system:
        if isinstance(system, list):
            system = " ".join(b.get("text","") for b in system if b.get("type")=="text")
        oai.append({"role": "system", "content": system})

    for msg in messages:
        role = msg["role"]
        content = msg.get("content", "")

        # Simple string content
        if isinstance(content, str):
            oai.append({"role": role, "content": content})
            continue

        # Array content — need to split into text, tool_use, tool_result, image
        if isinstance(content, list):
            text_parts = []
            image_parts = []
            tool_calls = []
            tool_results = []

            for block in content:
                btype = block.get("type", "")
                if btype == "text":
                    text_parts.append(block.get("text", ""))
                elif btype == "image":
                    # Anthropic image block: {"type":"image","source":{"type":"base64","media_type":"image/jpeg","data":"..."}}
                    src = block.get("source", {})
                    if src.get("type") == "base64":
                        data_url = f"data:{src.get('media_type','image/jpeg')};base64,{src['data']}"
                        image_parts.append({"type": "image_url", "image_url": {"url": data_url}})
                    elif src.get("type") == "url":
                        image_parts.append({"type": "image_url", "image_url": {"url": src["url"]}})
                elif btype == "image_url":
                    image_parts.append(block)
                elif btype == "tool_use":
                    tool_calls.append({
                        "id": block["id"],
                        "type": "function",
                        "function": {
                            "name": block["name"],
                            "arguments": json.dumps(block.get("input", {})),
                        }
                    })
                elif btype == "tool_result":
                    # Extract text from tool_result content
                    tr_content = block.get("content", "")
                    if isinstance(tr_content, list):
                        tr_content = "\n".join(
                            b.get("text","") for b in tr_content
                            if isinstance(b, dict) and b.get("type") == "text"
                        )
                    elif not isinstance(tr_content, str):
                        tr_content = str(tr_content)
                    tool_results.append({
                        "role": "tool",
                        "tool_call_id": block["tool_use_id"],
                        "content": tr_content,
                    })

            if role == "assistant":
                m = {"role": "assistant"}
                if text_parts:
                    m["content"] = "\n".join(text_parts)
                else:
                    m["content"] = ""
                if tool_calls:
                    m["tool_calls"] = tool_calls
                oai.append(m)
            elif role == "user":
                # User messages may contain text + images + tool_results
                if image_parts:
                    # Multi-modal: build OpenAI content array with images + text
                    multi_content = list(image_parts)
                    if text_parts:
                        multi_content.append({"type": "text", "text": "\n".join(text_parts)})
                    oai.append({"role": "user", "content": multi_content})
                elif text_parts:
                    oai.append({"role": "user", "content": "\n".join(text_parts)})
                for tr in tool_results:
                    oai.append(tr)
            else:
                oai.append({"role": role, "content": str(content)})

    return oai

# ── OpenAI → Anthropic conversion ──

def oai_response_to_anthropic(data, model):
    """Convert OpenAI completion response to Anthropic message response"""
    choice = data.get("choices", [{}])[0]
    message = choice.get("message", {})
    usage = data.get("usage", {})
    finish = choice.get("finish_reason", "stop")

    content_blocks = []

    # Text content
    text = message.get("content", "")
    if text:
        content_blocks.append({"type": "text", "text": text})

    # Tool calls
    for tc in message.get("tool_calls", []):
        func = tc.get("function", {})
        try:
            input_data = json.loads(func.get("arguments", "{}"))
        except json.JSONDecodeError:
            input_data = {}
        content_blocks.append({
            "type": "tool_use",
            "id": f"toolu_{uuid.uuid4().hex[:24]}",
            "name": func.get("name", ""),
            "input": input_data,
        })

    # Determine stop reason
    if finish == "tool_calls":
        stop_reason = "tool_use"
    else:
        stop_reason = "end_turn"

    return {
        "id": f"msg_{uuid.uuid4().hex[:24]}",
        "type": "message",
        "role": "assistant",
        "model": model,
        "content": content_blocks if content_blocks else [{"type": "text", "text": ""}],
        "stop_reason": stop_reason,
        "stop_sequence": None,
        "usage": {
            "input_tokens": usage.get("prompt_tokens", 0),
            "output_tokens": usage.get("completion_tokens", 0),
            "cache_creation_input_tokens": 0,
            "cache_read_input_tokens": 0,
        }
    }

# ── Handlers ──

async def handle_messages(request):
    body = await request.json()
    model = body.get("model", "claude-sonnet-4-6")
    stream = body.get("stream", False)
    tools = body.get("tools", None)
    backend = get_backend(model, body.get("messages", []))
    mlx_url = f"http://127.0.0.1:{backend['port']}/v1/chat/completions"
    log(f"POST /v1/messages model={model} -> {backend['label']} :{backend['port']} stream={stream} tools={len(tools) if tools else 0}")

    oai_body = {
        "model": backend["mlx_model"],
        "messages": convert_messages(body.get("messages", []), body.get("system", "")),
        "max_tokens": body.get("max_tokens", 4096),
        "chat_template_kwargs": {"enable_thinking": False},
    }
    if body.get("temperature") is not None:
        oai_body["temperature"] = body["temperature"]
    if tools:
        oai_body["tools"] = convert_tools(tools)

    if stream:
        return await handle_stream(request, oai_body, model, mlx_url)

    # Non-streaming
    async with ClientSession() as session:
        async with session.post(mlx_url, json=oai_body) as resp:
            data = await resp.json()

    return web.json_response(oai_response_to_anthropic(data, model))

async def handle_stream(request, oai_body, model, mlx_url):
    msg_id = f"msg_{uuid.uuid4().hex[:24]}"
    response = web.StreamResponse()
    response.headers["Content-Type"] = "text/event-stream"
    response.headers["Cache-Control"] = "no-cache"
    await response.prepare(request)

    async def send(event_type, data):
        await response.write(f"event: {event_type}\ndata: {json.dumps(data)}\n\n".encode())

    # message_start
    await send("message_start", {
        "type": "message_start",
        "message": {
            "id": msg_id, "type": "message", "role": "assistant",
            "model": model, "content": [], "stop_reason": None, "stop_sequence": None,
            "usage": {"input_tokens": 0, "output_tokens": 0,
                      "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0}
        }
    })

    oai_body["stream"] = True
    full_text = ""
    # Track tool calls being streamed: {index: {id, name, arguments}}
    tool_calls = {}
    content_index = 0  # Next Anthropic content block index
    text_block_started = False
    tool_blocks_started = {}  # index -> bool

    async with ClientSession() as session:
        async with session.post(mlx_url, json=oai_body) as resp:
            async for line in resp.content:
                line = line.decode().strip()
                if not line.startswith("data: "):
                    continue
                data_str = line[6:]
                if data_str == "[DONE]":
                    break
                try:
                    chunk = json.loads(data_str)
                    delta = chunk.get("choices", [{}])[0].get("delta", {})

                    # Text content
                    text = delta.get("content", "")
                    if text:
                        if not text_block_started:
                            await send("content_block_start", {
                                "type": "content_block_start",
                                "index": content_index,
                                "content_block": {"type": "text", "text": ""}
                            })
                            text_block_started = True
                        full_text += text
                        await send("content_block_delta", {
                            "type": "content_block_delta",
                            "index": content_index,
                            "delta": {"type": "text_delta", "text": text}
                        })

                    # Tool calls
                    for tc in delta.get("tool_calls", []):
                        idx = tc.get("index", 0)
                        if idx not in tool_calls:
                            tool_calls[idx] = {
                                "id": tc.get("id", f"toolu_{uuid.uuid4().hex[:24]}"),
                                "name": tc.get("function", {}).get("name", ""),
                                "arguments": "",
                            }
                        else:
                            # Accumulate arguments
                            tool_calls[idx]["arguments"] += tc.get("function", {}).get("arguments", "")

                        func = tc.get("function", {})
                        if func.get("name") and idx not in tool_blocks_started:
                            # Close text block if open
                            if text_block_started:
                                await send("content_block_stop", {
                                    "type": "content_block_stop",
                                    "index": content_index
                                })
                                content_index += 1
                                text_block_started = False

                            # Start tool_use block
                            tool_blocks_started[idx] = content_index
                            await send("content_block_start", {
                                "type": "content_block_start",
                                "index": content_index,
                                "content_block": {
                                    "type": "tool_use",
                                    "id": f"toolu_{uuid.uuid4().hex[:24]}",
                                    "name": func["name"],
                                    "input": {}
                                }
                            })
                            # Store the toolu_id for this block
                            tool_calls[idx]["block_index"] = content_index
                            content_index += 1

                        if func.get("arguments"):
                            block_idx = tool_calls[idx].get("block_index", content_index - 1)
                            await send("content_block_delta", {
                                "type": "content_block_delta",
                                "index": block_idx,
                                "delta": {
                                    "type": "input_json_delta",
                                    "partial_json": func["arguments"]
                                }
                            })
                except Exception as e:
                    log(f"Stream parse error: {e}")

    # Close open blocks
    if text_block_started:
        await send("content_block_stop", {"type": "content_block_stop", "index": 0})

    for idx, tc in tool_calls.items():
        block_idx = tc.get("block_index", idx + 1)
        await send("content_block_stop", {"type": "content_block_stop", "index": block_idx})

    # Determine stop reason
    stop_reason = "tool_use" if tool_calls else "end_turn"

    await send("message_delta", {
        "type": "message_delta",
        "delta": {"stop_reason": stop_reason, "stop_sequence": None},
        "usage": {"output_tokens": len(full_text) // 4 + sum(len(tc["arguments"]) // 4 for tc in tool_calls.values())}
    })
    await send("message_stop", {"type": "message_stop"})

    await response.write_eof()
    return response

async def handle_count_tokens(request):
    body = await request.json()
    log(f"POST /v1/messages/count_tokens")
    msgs = convert_messages(body.get("messages", []), body.get("system", ""))
    total = sum(len(m.get("content", "")) // 4 for m in msgs)
    return web.json_response({"input_tokens": total})

async def handle_models(request):
    log(f"GET /v1/models")
    return web.json_response({
        "data": [{"id": m, "object": "model", "created": 1677610602, "owned_by": "anthropic"}
                 for m in MODEL_ROUTES.keys()],
        "object": "list"
    })

async def catch_all(request):
    body = await request.text()
    log(f"CATCH-ALL {request.method} {request.path} body={body[:300]}")
    return web.json_response({"ok": True})

app = web.Application()
app.router.add_post("/v1/messages/count_tokens", handle_count_tokens)
app.router.add_post("/v1/messages", handle_messages)
app.router.add_get("/v1/models", handle_models)
app.router.add_route("*", "/{path:.*}", catch_all)

if __name__ == "__main__":
    for name, cfg in MODELS.items():
        log(f"  [{name}] {cfg['mlx_model']} -> :{cfg['port']} ({cfg['label']})")
    log(f"Anthropic proxy on :4001 (multi-model, tool_use)")
    web.run_app(app, host="0.0.0.0", port=4001, print=lambda x: log(x))
