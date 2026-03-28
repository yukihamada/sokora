#!/bin/bash
# ============================================================
# Local Claude Code Setup — Qwen3.5-122B on MLX
# ============================================================
# Apple Silicon Mac (64GB+ RAM) で Qwen3.5-122B-A10B-4bit を
# MLX で動かし、Claude Code のtool_use含め完全互換で使えるようにする。
#
# 使い方:
#   ssh user@mac "bash -s" < setup_local_claude.sh
#   または Mac 上で直接:
#   bash setup_local_claude.sh
#
# セットアップ後:
#   ~/ai.sh start   → MLX + プロキシ起動
#   ~/ai.sh stop    → 停止
#   cld              → ローカルAIでClaude Code起動
#   clc              → 本家AnthropicでClaude Code起動
# ============================================================

set -e

MODEL="mlx-community/Qwen3.5-122B-A10B-4bit"
MLX_PORT=5000
PROXY_PORT=4001
VENV="$HOME/mlx_env"

echo "========================================"
echo " Local Claude Code Setup"
echo " Model: $MODEL"
echo "========================================"

# -------------------------------------------------------
# 1. Homebrew + Python 3.11
# -------------------------------------------------------
echo "[1/6] Checking Homebrew & Python..."
export PATH="/opt/homebrew/bin:$PATH"

if ! command -v brew &>/dev/null; then
  echo "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

if ! brew list python@3.11 &>/dev/null; then
  echo "Installing Python 3.11..."
  brew install python@3.11
fi

# -------------------------------------------------------
# 2. venv + MLX + aiohttp
# -------------------------------------------------------
echo "[2/6] Setting up Python venv & dependencies..."
if [ ! -d "$VENV" ]; then
  python3.11 -m venv "$VENV"
fi

source "$VENV/bin/activate"
pip install --upgrade pip -q
pip install mlx-lm aiohttp -q
echo "  mlx-lm $(pip show mlx-lm 2>/dev/null | grep Version | cut -d' ' -f2)"

# -------------------------------------------------------
# 3. Download model (if not cached)
# -------------------------------------------------------
echo "[3/6] Checking model cache..."
if python3 -c "
from huggingface_hub import scan_cache_dir
repos = [i.repo_id for i in scan_cache_dir().repos]
exit(0 if '$MODEL' in repos else 1)
" 2>/dev/null; then
  echo "  Model already cached"
else
  echo "  Downloading $MODEL (this may take a while)..."
  python3 -c "from huggingface_hub import snapshot_download; snapshot_download('$MODEL')"
fi

# -------------------------------------------------------
# 4. Anthropic proxy (with tool_use support)
# -------------------------------------------------------
echo "[4/6] Writing Anthropic proxy..."
base64 -d << 'B64EOF' > "$HOME/anthropic_proxy.py"
IiIiQW50aHJvcGljIE1lc3NhZ2VzIEFQSSAtPiBPcGVuQUkgQ2hhdCBDb21wbGV0aW9ucyBwcm94eSBmb3IgTUxYClN1cHBvcnRzOiB0ZXh0LCBzdHJlYW1pbmcsIHRvb2xfdXNlL3Rvb2xfcmVzdWx0IGNvbnZlcnNpb24iIiIKaW1wb3J0IGpzb24sIHV1aWQsIHRpbWUKZnJvbSBhaW9odHRwIGltcG9ydCB3ZWIsIENsaWVudFNlc3Npb24KCk1MWF9VUkwgPSAiaHR0cDovLzEyNy4wLjAuMTo1MDAwL3YxL2NoYXQvY29tcGxldGlvbnMiCk1MWF9NT0RFTCA9ICJtbHgtY29tbXVuaXR5L1F3ZW4zLjUtMTIyQi1BMTBCLTRiaXQiCgpkZWYgbG9nKG1zZyk6CiAgICBwcmludChmIlt7dGltZS5zdHJmdGltZSgnJUg6JU06JVMnKX1dIHttc2d9IiwgZmx1c2g9VHJ1ZSkKCiMg4pSA4pSAIEFudGhyb3BpYyDihpIgT3BlbkFJIGNvbnZlcnNpb24g4pSA4pSACgpkZWYgY29udmVydF90b29scyhhbnRocm9waWNfdG9vbHMpOgogICAgIiIiQW50aHJvcGljIHRvb2xzIOKGkiBPcGVuQUkgdG9vbHMiIiIKICAgIGlmIG5vdCBhbnRocm9waWNfdG9vbHM6CiAgICAgICAgcmV0dXJuIE5vbmUKICAgIG9haV90b29scyA9IFtdCiAgICBmb3IgdCBpbiBhbnRocm9waWNfdG9vbHM6CiAgICAgICAgb2FpX3Rvb2xzLmFwcGVuZCh7CiAgICAgICAgICAgICJ0eXBlIjogImZ1bmN0aW9uIiwKICAgICAgICAgICAgImZ1bmN0aW9uIjogewogICAgICAgICAgICAgICAgIm5hbWUiOiB0WyJuYW1lIl0sCiAgICAgICAgICAgICAgICAiZGVzY3JpcHRpb24iOiB0LmdldCgiZGVzY3JpcHRpb24iLCAiIiksCiAgICAgICAgICAgICAgICAicGFyYW1ldGVycyI6IHQuZ2V0KCJpbnB1dF9zY2hlbWEiLCB7fSksCiAgICAgICAgICAgIH0KICAgICAgICB9KQogICAgcmV0dXJuIG9haV90b29scwoKZGVmIGNvbnZlcnRfbWVzc2FnZXMobWVzc2FnZXMsIHN5c3RlbT0iIik6CiAgICAiIiJBbnRocm9waWMgbWVzc2FnZXMg4oaSIE9wZW5BSSBtZXNzYWdlcyIiIgogICAgb2FpID0gW10KICAgIGlmIHN5c3RlbToKICAgICAgICBpZiBpc2luc3RhbmNlKHN5c3RlbSwgbGlzdCk6CiAgICAgICAgICAgIHN5c3RlbSA9ICIgIi5qb2luKGIuZ2V0KCJ0ZXh0IiwiIikgZm9yIGIgaW4gc3lzdGVtIGlmIGIuZ2V0KCJ0eXBlIik9PSJ0ZXh0IikKICAgICAgICBvYWkuYXBwZW5kKHsicm9sZSI6ICJzeXN0ZW0iLCAiY29udGVudCI6IHN5c3RlbX0pCgogICAgZm9yIG1zZyBpbiBtZXNzYWdlczoKICAgICAgICByb2xlID0gbXNnWyJyb2xlIl0KICAgICAgICBjb250ZW50ID0gbXNnLmdldCgiY29udGVudCIsICIiKQoKICAgICAgICAjIFNpbXBsZSBzdHJpbmcgY29udGVudAogICAgICAgIGlmIGlzaW5zdGFuY2UoY29udGVudCwgc3RyKToKICAgICAgICAgICAgb2FpLmFwcGVuZCh7InJvbGUiOiByb2xlLCAiY29udGVudCI6IGNvbnRlbnR9KQogICAgICAgICAgICBjb250aW51ZQoKICAgICAgICAjIEFycmF5IGNvbnRlbnQg4oCUIG5lZWQgdG8gc3BsaXQgaW50byB0ZXh0LCB0b29sX3VzZSwgdG9vbF9yZXN1bHQKICAgICAgICBpZiBpc2luc3RhbmNlKGNvbnRlbnQsIGxpc3QpOgogICAgICAgICAgICB0ZXh0X3BhcnRzID0gW10KICAgICAgICAgICAgdG9vbF9jYWxscyA9IFtdCiAgICAgICAgICAgIHRvb2xfcmVzdWx0cyA9IFtdCgogICAgICAgICAgICBmb3IgYmxvY2sgaW4gY29udGVudDoKICAgICAgICAgICAgICAgIGJ0eXBlID0gYmxvY2suZ2V0KCJ0eXBlIiwgIiIpCiAgICAgICAgICAgICAgICBpZiBidHlwZSA9PSAidGV4dCI6CiAgICAgICAgICAgICAgICAgICAgdGV4dF9wYXJ0cy5hcHBlbmQoYmxvY2suZ2V0KCJ0ZXh0IiwgIiIpKQogICAgICAgICAgICAgICAgZWxpZiBidHlwZSA9PSAidG9vbF91c2UiOgogICAgICAgICAgICAgICAgICAgIHRvb2xfY2FsbHMuYXBwZW5kKHsKICAgICAgICAgICAgICAgICAgICAgICAgImlkIjogYmxvY2tbImlkIl0sCiAgICAgICAgICAgICAgICAgICAgICAgICJ0eXBlIjogImZ1bmN0aW9uIiwKICAgICAgICAgICAgICAgICAgICAgICAgImZ1bmN0aW9uIjogewogICAgICAgICAgICAgICAgICAgICAgICAgICAgIm5hbWUiOiBibG9ja1sibmFtZSJdLAogICAgICAgICAgICAgICAgICAgICAgICAgICAgImFyZ3VtZW50cyI6IGpzb24uZHVtcHMoYmxvY2suZ2V0KCJpbnB1dCIsIHt9KSksCiAgICAgICAgICAgICAgICAgICAgICAgIH0KICAgICAgICAgICAgICAgICAgICB9KQogICAgICAgICAgICAgICAgZWxpZiBidHlwZSA9PSAidG9vbF9yZXN1bHQiOgogICAgICAgICAgICAgICAgICAgICMgRXh0cmFjdCB0ZXh0IGZyb20gdG9vbF9yZXN1bHQgY29udGVudAogICAgICAgICAgICAgICAgICAgIHRyX2NvbnRlbnQgPSBibG9jay5nZXQoImNvbnRlbnQiLCAiIikKICAgICAgICAgICAgICAgICAgICBpZiBpc2luc3RhbmNlKHRyX2NvbnRlbnQsIGxpc3QpOgogICAgICAgICAgICAgICAgICAgICAgICB0cl9jb250ZW50ID0gIlxuIi5qb2luKAogICAgICAgICAgICAgICAgICAgICAgICAgICAgYi5nZXQoInRleHQiLCIiKSBmb3IgYiBpbiB0cl9jb250ZW50CiAgICAgICAgICAgICAgICAgICAgICAgICAgICBpZiBpc2luc3RhbmNlKGIsIGRpY3QpIGFuZCBiLmdldCgidHlwZSIpID09ICJ0ZXh0IgogICAgICAgICAgICAgICAgICAgICAgICApCiAgICAgICAgICAgICAgICAgICAgZWxpZiBub3QgaXNpbnN0YW5jZSh0cl9jb250ZW50LCBzdHIpOgogICAgICAgICAgICAgICAgICAgICAgICB0cl9jb250ZW50ID0gc3RyKHRyX2NvbnRlbnQpCiAgICAgICAgICAgICAgICAgICAgdG9vbF9yZXN1bHRzLmFwcGVuZCh7CiAgICAgICAgICAgICAgICAgICAgICAgICJyb2xlIjogInRvb2wiLAogICAgICAgICAgICAgICAgICAgICAgICAidG9vbF9jYWxsX2lkIjogYmxvY2tbInRvb2xfdXNlX2lkIl0sCiAgICAgICAgICAgICAgICAgICAgICAgICJjb250ZW50IjogdHJfY29udGVudCwKICAgICAgICAgICAgICAgICAgICB9KQoKICAgICAgICAgICAgaWYgcm9sZSA9PSAiYXNzaXN0YW50IjoKICAgICAgICAgICAgICAgIG0gPSB7InJvbGUiOiAiYXNzaXN0YW50In0KICAgICAgICAgICAgICAgIGlmIHRleHRfcGFydHM6CiAgICAgICAgICAgICAgICAgICAgbVsiY29udGVudCJdID0gIlxuIi5qb2luKHRleHRfcGFydHMpCiAgICAgICAgICAgICAgICBlbHNlOgogICAgICAgICAgICAgICAgICAgIG1bImNvbnRlbnQiXSA9ICIiCiAgICAgICAgICAgICAgICBpZiB0b29sX2NhbGxzOgogICAgICAgICAgICAgICAgICAgIG1bInRvb2xfY2FsbHMiXSA9IHRvb2xfY2FsbHMKICAgICAgICAgICAgICAgIG9haS5hcHBlbmQobSkKICAgICAgICAgICAgZWxpZiByb2xlID09ICJ1c2VyIjoKICAgICAgICAgICAgICAgICMgVXNlciBtZXNzYWdlcyBtYXkgY29udGFpbiB0ZXh0ICsgdG9vbF9yZXN1bHRzCiAgICAgICAgICAgICAgICBpZiB0ZXh0X3BhcnRzOgogICAgICAgICAgICAgICAgICAgIG9haS5hcHBlbmQoeyJyb2xlIjogInVzZXIiLCAiY29udGVudCI6ICJcbiIuam9pbih0ZXh0X3BhcnRzKX0pCiAgICAgICAgICAgICAgICBmb3IgdHIgaW4gdG9vbF9yZXN1bHRzOgogICAgICAgICAgICAgICAgICAgIG9haS5hcHBlbmQodHIpCiAgICAgICAgICAgIGVsc2U6CiAgICAgICAgICAgICAgICBvYWkuYXBwZW5kKHsicm9sZSI6IHJvbGUsICJjb250ZW50Ijogc3RyKGNvbnRlbnQpfSkKCiAgICByZXR1cm4gb2FpCgojIOKUgOKUgCBPcGVuQUkg4oaSIEFudGhyb3BpYyBjb252ZXJzaW9uIOKUgOKUgAoKZGVmIG9haV9yZXNwb25zZV90b19hbnRocm9waWMoZGF0YSwgbW9kZWwpOgogICAgIiIiQ29udmVydCBPcGVuQUkgY29tcGxldGlvbiByZXNwb25zZSB0byBBbnRocm9waWMgbWVzc2FnZSByZXNwb25zZSIiIgogICAgY2hvaWNlID0gZGF0YS5nZXQoImNob2ljZXMiLCBbe31dKVswXQogICAgbWVzc2FnZSA9IGNob2ljZS5nZXQoIm1lc3NhZ2UiLCB7fSkKICAgIHVzYWdlID0gZGF0YS5nZXQoInVzYWdlIiwge30pCiAgICBmaW5pc2ggPSBjaG9pY2UuZ2V0KCJmaW5pc2hfcmVhc29uIiwgInN0b3AiKQoKICAgIGNvbnRlbnRfYmxvY2tzID0gW10KCiAgICAjIFRleHQgY29udGVudAogICAgdGV4dCA9IG1lc3NhZ2UuZ2V0KCJjb250ZW50IiwgIiIpCiAgICBpZiB0ZXh0OgogICAgICAgIGNvbnRlbnRfYmxvY2tzLmFwcGVuZCh7InR5cGUiOiAidGV4dCIsICJ0ZXh0IjogdGV4dH0pCgogICAgIyBUb29sIGNhbGxzCiAgICBmb3IgdGMgaW4gbWVzc2FnZS5nZXQoInRvb2xfY2FsbHMiLCBbXSk6CiAgICAgICAgZnVuYyA9IHRjLmdldCgiZnVuY3Rpb24iLCB7fSkKICAgICAgICB0cnk6CiAgICAgICAgICAgIGlucHV0X2RhdGEgPSBqc29uLmxvYWRzKGZ1bmMuZ2V0KCJhcmd1bWVudHMiLCAie30iKSkKICAgICAgICBleGNlcHQganNvbi5KU09ORGVjb2RlRXJyb3I6CiAgICAgICAgICAgIGlucHV0X2RhdGEgPSB7fQogICAgICAgIGNvbnRlbnRfYmxvY2tzLmFwcGVuZCh7CiAgICAgICAgICAgICJ0eXBlIjogInRvb2xfdXNlIiwKICAgICAgICAgICAgImlkIjogZiJ0b29sdV97dXVpZC51dWlkNCgpLmhleFs6MjRdfSIsCiAgICAgICAgICAgICJuYW1lIjogZnVuYy5nZXQoIm5hbWUiLCAiIiksCiAgICAgICAgICAgICJpbnB1dCI6IGlucHV0X2RhdGEsCiAgICAgICAgfSkKCiAgICAjIERldGVybWluZSBzdG9wIHJlYXNvbgogICAgaWYgZmluaXNoID09ICJ0b29sX2NhbGxzIjoKICAgICAgICBzdG9wX3JlYXNvbiA9ICJ0b29sX3VzZSIKICAgIGVsc2U6CiAgICAgICAgc3RvcF9yZWFzb24gPSAiZW5kX3R1cm4iCgogICAgcmV0dXJuIHsKICAgICAgICAiaWQiOiBmIm1zZ197dXVpZC51dWlkNCgpLmhleFs6MjRdfSIsCiAgICAgICAgInR5cGUiOiAibWVzc2FnZSIsCiAgICAgICAgInJvbGUiOiAiYXNzaXN0YW50IiwKICAgICAgICAibW9kZWwiOiBtb2RlbCwKICAgICAgICAiY29udGVudCI6IGNvbnRlbnRfYmxvY2tzIGlmIGNvbnRlbnRfYmxvY2tzIGVsc2UgW3sidHlwZSI6ICJ0ZXh0IiwgInRleHQiOiAiIn1dLAogICAgICAgICJzdG9wX3JlYXNvbiI6IHN0b3BfcmVhc29uLAogICAgICAgICJzdG9wX3NlcXVlbmNlIjogTm9uZSwKICAgICAgICAidXNhZ2UiOiB7CiAgICAgICAgICAgICJpbnB1dF90b2tlbnMiOiB1c2FnZS5nZXQoInByb21wdF90b2tlbnMiLCAwKSwKICAgICAgICAgICAgIm91dHB1dF90b2tlbnMiOiB1c2FnZS5nZXQoImNvbXBsZXRpb25fdG9rZW5zIiwgMCksCiAgICAgICAgICAgICJjYWNoZV9jcmVhdGlvbl9pbnB1dF90b2tlbnMiOiAwLAogICAgICAgICAgICAiY2FjaGVfcmVhZF9pbnB1dF90b2tlbnMiOiAwLAogICAgICAgIH0KICAgIH0KCiMg4pSA4pSAIEhhbmRsZXJzIOKUgOKUgAoKYXN5bmMgZGVmIGhhbmRsZV9tZXNzYWdlcyhyZXF1ZXN0KToKICAgIGJvZHkgPSBhd2FpdCByZXF1ZXN0Lmpzb24oKQogICAgbW9kZWwgPSBib2R5LmdldCgibW9kZWwiLCAiY2xhdWRlLXNvbm5ldC00LTYiKQogICAgc3RyZWFtID0gYm9keS5nZXQoInN0cmVhbSIsIEZhbHNlKQogICAgdG9vbHMgPSBib2R5LmdldCgidG9vbHMiLCBOb25lKQogICAgbG9nKGYiUE9TVCAvdjEvbWVzc2FnZXMgbW9kZWw9e21vZGVsfSBzdHJlYW09e3N0cmVhbX0gdG9vbHM9e2xlbih0b29scykgaWYgdG9vbHMgZWxzZSAwfSIpCgogICAgb2FpX2JvZHkgPSB7CiAgICAgICAgIm1vZGVsIjogTUxYX01PREVMLAogICAgICAgICJtZXNzYWdlcyI6IGNvbnZlcnRfbWVzc2FnZXMoYm9keS5nZXQoIm1lc3NhZ2VzIiwgW10pLCBib2R5LmdldCgic3lzdGVtIiwgIiIpKSwKICAgICAgICAibWF4X3Rva2VucyI6IGJvZHkuZ2V0KCJtYXhfdG9rZW5zIiwgNDA5NiksCiAgICAgICAgImNoYXRfdGVtcGxhdGVfa3dhcmdzIjogeyJlbmFibGVfdGhpbmtpbmciOiBGYWxzZX0sCiAgICB9CiAgICBpZiBib2R5LmdldCgidGVtcGVyYXR1cmUiKSBpcyBub3QgTm9uZToKICAgICAgICBvYWlfYm9keVsidGVtcGVyYXR1cmUiXSA9IGJvZHlbInRlbXBlcmF0dXJlIl0KICAgIGlmIHRvb2xzOgogICAgICAgIG9haV9ib2R5WyJ0b29scyJdID0gY29udmVydF90b29scyh0b29scykKCiAgICBpZiBzdHJlYW06CiAgICAgICAgcmV0dXJuIGF3YWl0IGhhbmRsZV9zdHJlYW0ocmVxdWVzdCwgb2FpX2JvZHksIG1vZGVsKQoKICAgICMgTm9uLXN0cmVhbWluZwogICAgYXN5bmMgd2l0aCBDbGllbnRTZXNzaW9uKCkgYXMgc2Vzc2lvbjoKICAgICAgICBhc3luYyB3aXRoIHNlc3Npb24ucG9zdChNTFhfVVJMLCBqc29uPW9haV9ib2R5KSBhcyByZXNwOgogICAgICAgICAgICBkYXRhID0gYXdhaXQgcmVzcC5qc29uKCkKCiAgICByZXR1cm4gd2ViLmpzb25fcmVzcG9uc2Uob2FpX3Jlc3BvbnNlX3RvX2FudGhyb3BpYyhkYXRhLCBtb2RlbCkpCgphc3luYyBkZWYgaGFuZGxlX3N0cmVhbShyZXF1ZXN0LCBvYWlfYm9keSwgbW9kZWwpOgogICAgbXNnX2lkID0gZiJtc2dfe3V1aWQudXVpZDQoKS5oZXhbOjI0XX0iCiAgICByZXNwb25zZSA9IHdlYi5TdHJlYW1SZXNwb25zZSgpCiAgICByZXNwb25zZS5oZWFkZXJzWyJDb250ZW50LVR5cGUiXSA9ICJ0ZXh0L2V2ZW50LXN0cmVhbSIKICAgIHJlc3BvbnNlLmhlYWRlcnNbIkNhY2hlLUNvbnRyb2wiXSA9ICJuby1jYWNoZSIKICAgIGF3YWl0IHJlc3BvbnNlLnByZXBhcmUocmVxdWVzdCkKCiAgICBhc3luYyBkZWYgc2VuZChldmVudF90eXBlLCBkYXRhKToKICAgICAgICBhd2FpdCByZXNwb25zZS53cml0ZShmImV2ZW50OiB7ZXZlbnRfdHlwZX1cbmRhdGE6IHtqc29uLmR1bXBzKGRhdGEpfVxuXG4iLmVuY29kZSgpKQoKICAgICMgbWVzc2FnZV9zdGFydAogICAgYXdhaXQgc2VuZCgibWVzc2FnZV9zdGFydCIsIHsKICAgICAgICAidHlwZSI6ICJtZXNzYWdlX3N0YXJ0IiwKICAgICAgICAibWVzc2FnZSI6IHsKICAgICAgICAgICAgImlkIjogbXNnX2lkLCAidHlwZSI6ICJtZXNzYWdlIiwgInJvbGUiOiAiYXNzaXN0YW50IiwKICAgICAgICAgICAgIm1vZGVsIjogbW9kZWwsICJjb250ZW50IjogW10sICJzdG9wX3JlYXNvbiI6IE5vbmUsICJzdG9wX3NlcXVlbmNlIjogTm9uZSwKICAgICAgICAgICAgInVzYWdlIjogeyJpbnB1dF90b2tlbnMiOiAwLCAib3V0cHV0X3Rva2VucyI6IDAsCiAgICAgICAgICAgICAgICAgICAgICAiY2FjaGVfY3JlYXRpb25faW5wdXRfdG9rZW5zIjogMCwgImNhY2hlX3JlYWRfaW5wdXRfdG9rZW5zIjogMH0KICAgICAgICB9CiAgICB9KQoKICAgIG9haV9ib2R5WyJzdHJlYW0iXSA9IFRydWUKICAgIGZ1bGxfdGV4dCA9ICIiCiAgICAjIFRyYWNrIHRvb2wgY2FsbHMgYmVpbmcgc3RyZWFtZWQ6IHtpbmRleDoge2lkLCBuYW1lLCBhcmd1bWVudHN9fQogICAgdG9vbF9jYWxscyA9IHt9CiAgICBjb250ZW50X2luZGV4ID0gMCAgIyBOZXh0IEFudGhyb3BpYyBjb250ZW50IGJsb2NrIGluZGV4CiAgICB0ZXh0X2Jsb2NrX3N0YXJ0ZWQgPSBGYWxzZQogICAgdG9vbF9ibG9ja3Nfc3RhcnRlZCA9IHt9ICAjIGluZGV4IC0+IGJvb2wKCiAgICBhc3luYyB3aXRoIENsaWVudFNlc3Npb24oKSBhcyBzZXNzaW9uOgogICAgICAgIGFzeW5jIHdpdGggc2Vzc2lvbi5wb3N0KE1MWF9VUkwsIGpzb249b2FpX2JvZHkpIGFzIHJlc3A6CiAgICAgICAgICAgIGFzeW5jIGZvciBsaW5lIGluIHJlc3AuY29udGVudDoKICAgICAgICAgICAgICAgIGxpbmUgPSBsaW5lLmRlY29kZSgpLnN0cmlwKCkKICAgICAgICAgICAgICAgIGlmIG5vdCBsaW5lLnN0YXJ0c3dpdGgoImRhdGE6ICIpOgogICAgICAgICAgICAgICAgICAgIGNvbnRpbnVlCiAgICAgICAgICAgICAgICBkYXRhX3N0ciA9IGxpbmVbNjpdCiAgICAgICAgICAgICAgICBpZiBkYXRhX3N0ciA9PSAiW0RPTkVdIjoKICAgICAgICAgICAgICAgICAgICBicmVhawogICAgICAgICAgICAgICAgdHJ5OgogICAgICAgICAgICAgICAgICAgIGNodW5rID0ganNvbi5sb2FkcyhkYXRhX3N0cikKICAgICAgICAgICAgICAgICAgICBkZWx0YSA9IGNodW5rLmdldCgiY2hvaWNlcyIsIFt7fV0pWzBdLmdldCgiZGVsdGEiLCB7fSkKCiAgICAgICAgICAgICAgICAgICAgIyBUZXh0IGNvbnRlbnQKICAgICAgICAgICAgICAgICAgICB0ZXh0ID0gZGVsdGEuZ2V0KCJjb250ZW50IiwgIiIpCiAgICAgICAgICAgICAgICAgICAgaWYgdGV4dDoKICAgICAgICAgICAgICAgICAgICAgICAgaWYgbm90IHRleHRfYmxvY2tfc3RhcnRlZDoKICAgICAgICAgICAgICAgICAgICAgICAgICAgIGF3YWl0IHNlbmQoImNvbnRlbnRfYmxvY2tfc3RhcnQiLCB7CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgInR5cGUiOiAiY29udGVudF9ibG9ja19zdGFydCIsCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgImluZGV4IjogY29udGVudF9pbmRleCwKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAiY29udGVudF9ibG9jayI6IHsidHlwZSI6ICJ0ZXh0IiwgInRleHQiOiAiIn0KICAgICAgICAgICAgICAgICAgICAgICAgICAgIH0pCiAgICAgICAgICAgICAgICAgICAgICAgICAgICB0ZXh0X2Jsb2NrX3N0YXJ0ZWQgPSBUcnVlCiAgICAgICAgICAgICAgICAgICAgICAgIGZ1bGxfdGV4dCArPSB0ZXh0CiAgICAgICAgICAgICAgICAgICAgICAgIGF3YWl0IHNlbmQoImNvbnRlbnRfYmxvY2tfZGVsdGEiLCB7CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAidHlwZSI6ICJjb250ZW50X2Jsb2NrX2RlbHRhIiwKICAgICAgICAgICAgICAgICAgICAgICAgICAgICJpbmRleCI6IGNvbnRlbnRfaW5kZXgsCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAiZGVsdGEiOiB7InR5cGUiOiAidGV4dF9kZWx0YSIsICJ0ZXh0IjogdGV4dH0KICAgICAgICAgICAgICAgICAgICAgICAgfSkKCiAgICAgICAgICAgICAgICAgICAgIyBUb29sIGNhbGxzCiAgICAgICAgICAgICAgICAgICAgZm9yIHRjIGluIGRlbHRhLmdldCgidG9vbF9jYWxscyIsIFtdKToKICAgICAgICAgICAgICAgICAgICAgICAgaWR4ID0gdGMuZ2V0KCJpbmRleCIsIDApCiAgICAgICAgICAgICAgICAgICAgICAgIGlmIGlkeCBub3QgaW4gdG9vbF9jYWxsczoKICAgICAgICAgICAgICAgICAgICAgICAgICAgIHRvb2xfY2FsbHNbaWR4XSA9IHsKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAiaWQiOiB0Yy5nZXQoImlkIiwgZiJ0b29sdV97dXVpZC51dWlkNCgpLmhleFs6MjRdfSIpLAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICJuYW1lIjogdGMuZ2V0KCJmdW5jdGlvbiIsIHt9KS5nZXQoIm5hbWUiLCAiIiksCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgImFyZ3VtZW50cyI6ICIiLAogICAgICAgICAgICAgICAgICAgICAgICAgICAgfQogICAgICAgICAgICAgICAgICAgICAgICBlbHNlOgogICAgICAgICAgICAgICAgICAgICAgICAgICAgIyBBY2N1bXVsYXRlIGFyZ3VtZW50cwogICAgICAgICAgICAgICAgICAgICAgICAgICAgdG9vbF9jYWxsc1tpZHhdWyJhcmd1bWVudHMiXSArPSB0Yy5nZXQoImZ1bmN0aW9uIiwge30pLmdldCgiYXJndW1lbnRzIiwgIiIpCgogICAgICAgICAgICAgICAgICAgICAgICBmdW5jID0gdGMuZ2V0KCJmdW5jdGlvbiIsIHt9KQogICAgICAgICAgICAgICAgICAgICAgICBpZiBmdW5jLmdldCgibmFtZSIpIGFuZCBpZHggbm90IGluIHRvb2xfYmxvY2tzX3N0YXJ0ZWQ6CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAjIENsb3NlIHRleHQgYmxvY2sgaWYgb3BlbgogICAgICAgICAgICAgICAgICAgICAgICAgICAgaWYgdGV4dF9ibG9ja19zdGFydGVkOgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIGF3YWl0IHNlbmQoImNvbnRlbnRfYmxvY2tfc3RvcCIsIHsKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgInR5cGUiOiAiY29udGVudF9ibG9ja19zdG9wIiwKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgImluZGV4IjogY29udGVudF9pbmRleAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIH0pCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgY29udGVudF9pbmRleCArPSAxCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgdGV4dF9ibG9ja19zdGFydGVkID0gRmFsc2UKCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAjIFN0YXJ0IHRvb2xfdXNlIGJsb2NrCiAgICAgICAgICAgICAgICAgICAgICAgICAgICB0b29sX2Jsb2Nrc19zdGFydGVkW2lkeF0gPSBjb250ZW50X2luZGV4CiAgICAgICAgICAgICAgICAgICAgICAgICAgICBhd2FpdCBzZW5kKCJjb250ZW50X2Jsb2NrX3N0YXJ0IiwgewogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICJ0eXBlIjogImNvbnRlbnRfYmxvY2tfc3RhcnQiLAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICJpbmRleCI6IGNvbnRlbnRfaW5kZXgsCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgImNvbnRlbnRfYmxvY2siOiB7CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICJ0eXBlIjogInRvb2xfdXNlIiwKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgImlkIjogZiJ0b29sdV97dXVpZC51dWlkNCgpLmhleFs6MjRdfSIsCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICJuYW1lIjogZnVuY1sibmFtZSJdLAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAiaW5wdXQiOiB7fQogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIH0KICAgICAgICAgICAgICAgICAgICAgICAgICAgIH0pCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAjIFN0b3JlIHRoZSB0b29sdV9pZCBmb3IgdGhpcyBibG9jawogICAgICAgICAgICAgICAgICAgICAgICAgICAgdG9vbF9jYWxsc1tpZHhdWyJibG9ja19pbmRleCJdID0gY29udGVudF9pbmRleAogICAgICAgICAgICAgICAgICAgICAgICAgICAgY29udGVudF9pbmRleCArPSAxCgogICAgICAgICAgICAgICAgICAgICAgICBpZiBmdW5jLmdldCgiYXJndW1lbnRzIik6CiAgICAgICAgICAgICAgICAgICAgICAgICAgICBibG9ja19pZHggPSB0b29sX2NhbGxzW2lkeF0uZ2V0KCJibG9ja19pbmRleCIsIGNvbnRlbnRfaW5kZXggLSAxKQogICAgICAgICAgICAgICAgICAgICAgICAgICAgYXdhaXQgc2VuZCgiY29udGVudF9ibG9ja19kZWx0YSIsIHsKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAidHlwZSI6ICJjb250ZW50X2Jsb2NrX2RlbHRhIiwKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAiaW5kZXgiOiBibG9ja19pZHgsCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgImRlbHRhIjogewogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAidHlwZSI6ICJpbnB1dF9qc29uX2RlbHRhIiwKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgInBhcnRpYWxfanNvbiI6IGZ1bmNbImFyZ3VtZW50cyJdCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgfQogICAgICAgICAgICAgICAgICAgICAgICAgICAgfSkKICAgICAgICAgICAgICAgIGV4Y2VwdCBFeGNlcHRpb24gYXMgZToKICAgICAgICAgICAgICAgICAgICBsb2coZiJTdHJlYW0gcGFyc2UgZXJyb3I6IHtlfSIpCgogICAgIyBDbG9zZSBvcGVuIGJsb2NrcwogICAgaWYgdGV4dF9ibG9ja19zdGFydGVkOgogICAgICAgIGF3YWl0IHNlbmQoImNvbnRlbnRfYmxvY2tfc3RvcCIsIHsidHlwZSI6ICJjb250ZW50X2Jsb2NrX3N0b3AiLCAiaW5kZXgiOiAwfSkKCiAgICBmb3IgaWR4LCB0YyBpbiB0b29sX2NhbGxzLml0ZW1zKCk6CiAgICAgICAgYmxvY2tfaWR4ID0gdGMuZ2V0KCJibG9ja19pbmRleCIsIGlkeCArIDEpCiAgICAgICAgYXdhaXQgc2VuZCgiY29udGVudF9ibG9ja19zdG9wIiwgeyJ0eXBlIjogImNvbnRlbnRfYmxvY2tfc3RvcCIsICJpbmRleCI6IGJsb2NrX2lkeH0pCgogICAgIyBEZXRlcm1pbmUgc3RvcCByZWFzb24KICAgIHN0b3BfcmVhc29uID0gInRvb2xfdXNlIiBpZiB0b29sX2NhbGxzIGVsc2UgImVuZF90dXJuIgoKICAgIGF3YWl0IHNlbmQoIm1lc3NhZ2VfZGVsdGEiLCB7CiAgICAgICAgInR5cGUiOiAibWVzc2FnZV9kZWx0YSIsCiAgICAgICAgImRlbHRhIjogeyJzdG9wX3JlYXNvbiI6IHN0b3BfcmVhc29uLCAic3RvcF9zZXF1ZW5jZSI6IE5vbmV9LAogICAgICAgICJ1c2FnZSI6IHsib3V0cHV0X3Rva2VucyI6IGxlbihmdWxsX3RleHQpIC8vIDQgKyBzdW0obGVuKHRjWyJhcmd1bWVudHMiXSkgLy8gNCBmb3IgdGMgaW4gdG9vbF9jYWxscy52YWx1ZXMoKSl9CiAgICB9KQogICAgYXdhaXQgc2VuZCgibWVzc2FnZV9zdG9wIiwgeyJ0eXBlIjogIm1lc3NhZ2Vfc3RvcCJ9KQoKICAgIGF3YWl0IHJlc3BvbnNlLndyaXRlX2VvZigpCiAgICByZXR1cm4gcmVzcG9uc2UKCmFzeW5jIGRlZiBoYW5kbGVfY291bnRfdG9rZW5zKHJlcXVlc3QpOgogICAgYm9keSA9IGF3YWl0IHJlcXVlc3QuanNvbigpCiAgICBsb2coZiJQT1NUIC92MS9tZXNzYWdlcy9jb3VudF90b2tlbnMiKQogICAgbXNncyA9IGNvbnZlcnRfbWVzc2FnZXMoYm9keS5nZXQoIm1lc3NhZ2VzIiwgW10pLCBib2R5LmdldCgic3lzdGVtIiwgIiIpKQogICAgdG90YWwgPSBzdW0obGVuKG0uZ2V0KCJjb250ZW50IiwgIiIpKSAvLyA0IGZvciBtIGluIG1zZ3MpCiAgICByZXR1cm4gd2ViLmpzb25fcmVzcG9uc2UoeyJpbnB1dF90b2tlbnMiOiB0b3RhbH0pCgphc3luYyBkZWYgaGFuZGxlX21vZGVscyhyZXF1ZXN0KToKICAgIGxvZyhmIkdFVCAvdjEvbW9kZWxzIikKICAgIHJldHVybiB3ZWIuanNvbl9yZXNwb25zZSh7CiAgICAgICAgImRhdGEiOiBbeyJpZCI6IG0sICJvYmplY3QiOiAibW9kZWwiLCAiY3JlYXRlZCI6IDE2Nzc2MTA2MDIsICJvd25lZF9ieSI6ICJhbnRocm9waWMifQogICAgICAgICAgICAgICAgIGZvciBtIGluIFsiY2xhdWRlLXNvbm5ldC00LTYiLCJjbGF1ZGUtb3B1cy00LTYiLCJjbGF1ZGUtMy01LXNvbm5ldC0yMDI0MTAyMiJdXSwKICAgICAgICAib2JqZWN0IjogImxpc3QiCiAgICB9KQoKYXN5bmMgZGVmIGNhdGNoX2FsbChyZXF1ZXN0KToKICAgIGJvZHkgPSBhd2FpdCByZXF1ZXN0LnRleHQoKQogICAgbG9nKGYiQ0FUQ0gtQUxMIHtyZXF1ZXN0Lm1ldGhvZH0ge3JlcXVlc3QucGF0aH0gYm9keT17Ym9keVs6MzAwXX0iKQogICAgcmV0dXJuIHdlYi5qc29uX3Jlc3BvbnNlKHsib2siOiBUcnVlfSkKCmFwcCA9IHdlYi5BcHBsaWNhdGlvbigpCmFwcC5yb3V0ZXIuYWRkX3Bvc3QoIi92MS9tZXNzYWdlcy9jb3VudF90b2tlbnMiLCBoYW5kbGVfY291bnRfdG9rZW5zKQphcHAucm91dGVyLmFkZF9wb3N0KCIvdjEvbWVzc2FnZXMiLCBoYW5kbGVfbWVzc2FnZXMpCmFwcC5yb3V0ZXIuYWRkX2dldCgiL3YxL21vZGVscyIsIGhhbmRsZV9tb2RlbHMpCmFwcC5yb3V0ZXIuYWRkX3JvdXRlKCIqIiwgIi97cGF0aDouKn0iLCBjYXRjaF9hbGwpCgppZiBfX25hbWVfXyA9PSAiX19tYWluX18iOgogICAgbG9nKCJBbnRocm9waWMgcHJveHkgb24gOjQwMDEgLT4gTUxYIDo1MDAwICh3aXRoIHRvb2xfdXNlIHN1cHBvcnQpIikKICAgIHdlYi5ydW5fYXBwKGFwcCwgaG9zdD0iMC4wLjAuMCIsIHBvcnQ9NDAwMSwgcHJpbnQ9bGFtYmRhIHg6IGxvZyh4KSkK
B64EOF

# -------------------------------------------------------
# 5. ai.sh (start/stop/status/test)
# -------------------------------------------------------
echo "[5/6] Writing ~/ai.sh..."
cat > "$HOME/ai.sh" << 'SHEOF'
#!/bin/bash
MODEL="mlx-community/Qwen3.5-122B-A10B-4bit"
MLX_PORT=5000
PROXY_PORT=4001
VENV=~/mlx_env/bin/activate

start() {
  if pgrep -f "mlx_lm.server" > /dev/null; then
    echo "Already running. ~/ai.sh status"
    return 1
  fi

  source "$VENV"

  echo "MLX starting ($MODEL)..."
  nohup mlx_lm.server --model "$MODEL" --port $MLX_PORT > ~/mlx_server.log 2>&1 &
  for i in $(seq 1 40); do
    curl -s http://127.0.0.1:$MLX_PORT/v1/models 2>/dev/null | grep -q Qwen && break
    [ $i -eq 40 ] && { echo "MLX timeout"; tail -5 ~/mlx_server.log; return 1; }
    sleep 3
  done
  echo "MLX ready"

  echo "Proxy starting..."
  nohup python3 ~/anthropic_proxy.py > ~/proxy.log 2>&1 &
  sleep 2

  IP=$(ipconfig getifaddr en0 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}')
  echo ""
  echo "========================================"
  echo " Ready!"
  echo " Local:  http://127.0.0.1:$PROXY_PORT"
  echo " LAN:    http://$IP:$PROXY_PORT"
  echo "========================================"
  echo " cld  -> local AI (tool_use supported)"
  echo " clc  -> Anthropic cloud"
  echo "========================================"
}

stop() {
  pkill -f "mlx_lm.server" 2>/dev/null
  pkill -f "anthropic_proxy" 2>/dev/null
  echo "Stopped"
}

status() {
  pgrep -f "mlx_lm.server" > /dev/null && echo "MLX: running" || echo "MLX: stopped"
  pgrep -f "anthropic_proxy" > /dev/null && echo "Proxy: running (:$PROXY_PORT)" || echo "Proxy: stopped"
}

test_it() {
  R=$(curl -s http://127.0.0.1:$PROXY_PORT/v1/messages \
    -H "Content-Type: application/json" \
    -H "x-api-key: dummy" \
    -H "anthropic-version: 2023-06-01" \
    -d '{"model":"claude-sonnet-4-6","messages":[{"role":"user","content":"1+1=?"}],"max_tokens":20}')
  C=$(echo "$R" | python3 -c 'import sys,json;print(json.load(sys.stdin)["content"][0]["text"])' 2>/dev/null)
  [ -n "$C" ] && echo "OK: $C" || echo "Error: $R"
}

case "${1:-start}" in
  start) start ;; stop) stop ;; status) status ;; test) test_it ;; restart) stop; sleep 2; start ;;
  *) echo "~/ai.sh [start|stop|status|test|restart]" ;;
esac
SHEOF
chmod +x "$HOME/ai.sh"

# -------------------------------------------------------
# 6. Shell aliases + Claude Code settings
# -------------------------------------------------------
echo "[6/6] Configuring shell & Claude Code..."

cat > "$HOME/ai-switch.py" << 'SWEOF'
#!/usr/bin/env python3
import json, sys, os
SETTINGS = os.path.expanduser("~/.claude/settings.json")
def switch(mode):
    try:
        with open(SETTINGS) as f: d = json.load(f)
    except: d = {}
    if mode == "local":
        d["env"] = {"ANTHROPIC_BASE_URL": "http://127.0.0.1:4001", "ANTHROPIC_API_KEY": "sk-ant-dummy"}
        print("-> Local Qwen3.5 (MLX)")
    elif mode == "cloud":
        d.pop("env", None)
        print("-> Anthropic Cloud")
    else:
        print("Usage: ai-switch.py [local|cloud]"); return
    os.makedirs(os.path.dirname(SETTINGS), exist_ok=True)
    with open(SETTINGS, "w") as f: json.dump(d, f, indent=2)
if __name__ == "__main__":
    switch(sys.argv[1] if len(sys.argv) > 1 else "")
SWEOF
chmod +x "$HOME/ai-switch.py"

MARKER="# === Local Claude Code ==="
if ! grep -q "$MARKER" "$HOME/.zshrc" 2>/dev/null; then
  cat >> "$HOME/.zshrc" << 'RCEOF'

# === Local Claude Code ===
export PATH="/opt/homebrew/bin:$PATH"
ai-local() { python3 ~/ai-switch.py local; export ANTHROPIC_BASE_URL=http://127.0.0.1:4001; export ANTHROPIC_API_KEY=sk-ant-dummy; }
ai-cloud() { python3 ~/ai-switch.py cloud; unset ANTHROPIC_BASE_URL; unset ANTHROPIC_API_KEY; }
alias cld='ai-local && claude --dangerously-skip-permissions'
alias clc='ai-cloud && claude'
RCEOF
  echo "  Added aliases to ~/.zshrc"
else
  echo "  ~/.zshrc already configured"
fi

mkdir -p "$HOME/.claude"
python3 "$HOME/ai-switch.py" local

echo ""
echo "========================================"
echo " Setup complete!"
echo "========================================"
echo ""
echo " 1. ~/ai.sh start   -> Start MLX + proxy"
echo " 2. cld              -> Claude Code (local, tool_use OK)"
echo "    clc              -> Claude Code (Anthropic cloud)"
echo " 3. ~/ai.sh stop     -> Stop everything"
echo ""
echo " First run: ~/ai.sh start"
echo "========================================"
