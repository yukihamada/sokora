"""VLM server using mlx-vlm"""
import json, time, base64, tempfile, os
from aiohttp import web, ClientSession

MODEL_ID = "mlx-community/Qwen3-VL-8B-Instruct-4bit"

def log(msg):
    print(f"[{time.strftime('%H:%M:%S')}] VLM: {msg}", flush=True)

# Load model at import time (before server starts)
log(f"Loading {MODEL_ID}...")
from mlx_vlm import load, generate, apply_chat_template
model, processor = load(MODEL_ID)
log("Model loaded")

async def download_image(url):
    async with ClientSession() as session:
        async with session.get(url, headers={"User-Agent": "Mozilla/5.0"}) as resp:
            data = await resp.read()
            tmp = tempfile.NamedTemporaryFile(suffix=".jpg", delete=False)
            tmp.write(data)
            tmp.close()
            return tmp.name

async def handle_chat(request):
    body = await request.json()
    messages = body.get("messages", [])
    max_tokens = body.get("max_tokens", 256)

    images = []
    text_parts = []
    temp_files = []

    for msg in messages:
        content = msg.get("content", "")
        if isinstance(content, str):
            text_parts.append(content)
        elif isinstance(content, list):
            for block in content:
                btype = block.get("type", "")
                if btype == "text":
                    text_parts.append(block["text"])
                elif btype == "image_url":
                    url = block["image_url"]["url"]
                    if url.startswith("data:"):
                        _, b64data = url.split(",", 1)
                        tmp = tempfile.NamedTemporaryFile(suffix=".jpg", delete=False)
                        tmp.write(base64.b64decode(b64data))
                        tmp.close()
                        images.append(tmp.name)
                        temp_files.append(tmp.name)
                    else:
                        path = await download_image(url)
                        images.append(path)
                        temp_files.append(path)
                elif btype == "image" and block.get("source", {}).get("type") == "base64":
                    tmp = tempfile.NamedTemporaryFile(suffix=".jpg", delete=False)
                    tmp.write(base64.b64decode(block["source"]["data"]))
                    tmp.close()
                    images.append(tmp.name)
                    temp_files.append(tmp.name)

    prompt = "\n".join(text_parts) or "Describe this image."
    log(f"images={len(images)} prompt={prompt[:80]}")

    try:
        formatted = apply_chat_template(processor, model.config, prompt, num_images=len(images))
        img_arg = images if len(images) > 1 else (images[0] if images else None)
        result = generate(model, processor, formatted, image=img_arg, max_tokens=max_tokens, verbose=False)
        output = result.text if hasattr(result, "text") else str(result)
    except Exception as e:
        log(f"Error: {e}")
        import traceback; traceback.print_exc()
        output = f"Error: {e}"

    for f in temp_files:
        try: os.unlink(f)
        except: pass

    return web.json_response({
        "id": "chatcmpl-vlm", "object": "chat.completion", "model": MODEL_ID,
        "choices": [{"index": 0, "finish_reason": "stop",
                     "message": {"role": "assistant", "content": output}}],
        "usage": {"prompt_tokens": 0, "completion_tokens": len(output)//4, "total_tokens": 0}
    })

async def handle_models(request):
    return web.json_response({"data": [{"id": MODEL_ID, "object": "model"}], "object": "list"})

app = web.Application()
app.router.add_post("/v1/chat/completions", handle_chat)
app.router.add_get("/v1/models", handle_models)

if __name__ == "__main__":
    log(f"Starting on :5002")
    web.run_app(app, host="0.0.0.0", port=5002, print=lambda x: log(x))
