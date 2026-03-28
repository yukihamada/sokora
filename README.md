# Local Claude Code with MLX

Run Claude Code locally on Apple Silicon Mac using Qwen3.5-122B via MLX. Zero API costs, full tool_use support, complete offline operation.

## What This Does

```
Claude Code  -->  Anthropic Proxy (:4001)  -->  MLX Server (:5000)  -->  Qwen3.5-122B
  (tool_use)      (Anthropic -> OpenAI)         (Apple GPU)              (4-bit, ~60GB RAM)
```

- Translates Anthropic Messages API to OpenAI format for MLX
- Supports streaming, tool_use/tool_result, system prompts
- Claude Code runs commands, reads/writes files, just like with the real API
- Switch between local and cloud with one command

## Requirements

- Apple Silicon Mac with 64GB+ RAM (128GB recommended for 122B model)
- macOS 14+
- ~40GB disk space for model weights

## Quick Start

```bash
# One-command setup (installs everything)
bash setup.sh

# Start the AI server
~/ai.sh start

# Launch Claude Code (local)
cld

# Switch to Anthropic cloud
clc
```

## Setup from Remote

```bash
ssh user@your-mac "bash -s" < setup.sh
```

## Commands

| Command | Description |
|---------|-------------|
| `~/ai.sh start` | Start MLX + Anthropic proxy |
| `~/ai.sh stop` | Stop everything |
| `~/ai.sh status` | Check running status |
| `~/ai.sh test` | Quick inference test |
| `~/ai.sh restart` | Restart all services |
| `cld` | Claude Code with local AI |
| `clc` | Claude Code with Anthropic cloud |
| `ai-local` | Switch to local (no launch) |
| `ai-cloud` | Switch to cloud (no launch) |

## Architecture

### Anthropic Proxy (`anthropic_proxy.py`)

A lightweight aiohttp server that translates between Anthropic and OpenAI API formats:

- `POST /v1/messages` - Chat completions (streaming + non-streaming)
- `POST /v1/messages/count_tokens` - Token counting
- `GET /v1/models` - Model listing

**Tool use conversion:**

| Anthropic | OpenAI |
|-----------|--------|
| `tools[].input_schema` | `tools[].function.parameters` |
| `content[].type: "tool_use"` | `message.tool_calls[]` |
| `content[].type: "tool_result"` | `role: "tool"` messages |
| `stop_reason: "tool_use"` | `finish_reason: "tool_calls"` |

### MLX Server

Uses `mlx-lm` to serve the model with Apple GPU acceleration. The Qwen3.5-122B-A10B-4bit model uses Mixture of Experts (10B active parameters out of 122B total), making it fast on Apple Silicon while maintaining high quality.

## Model

**Qwen3.5-122B-A10B-4bit** (via mlx-community)
- 122B total parameters, ~10B active (MoE)
- 4-bit quantization, ~40GB on disk
- ~60GB RAM usage at runtime
- Supports 100+ languages, strong at code generation
- Native function/tool calling support

## Customization

### Using a different model

Edit `MODEL` in `setup.sh` and `anthropic_proxy.py`:

```bash
# Smaller model (32GB+ RAM)
MODEL="mlx-community/Qwen3-32B-4bit"

# Even smaller (16GB+ RAM)
MODEL="mlx-community/Qwen3-8B-4bit"
```

### Changing ports

Edit `MLX_PORT` and `PROXY_PORT` in `~/ai.sh`.

## Troubleshooting

**"ECONNREFUSED"** - Server not running. Run `~/ai.sh start`.

**"MLX timeout"** - Model still loading. Check `tail -f ~/mlx_server.log`.

**Tool calls not executing** - Make sure you're using `--dangerously-skip-permissions` flag.

**Out of memory** - The 122B model needs ~60GB RAM. Try a smaller model.

## License

MIT
