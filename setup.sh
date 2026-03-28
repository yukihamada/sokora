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
IiIiQW50aHJvcGljIE1lc3NhZ2VzIEFQSSAtPiBPcGVuQUkgQ2hhdCBDb21wbGV0aW9ucyBwcm94eSBmb3IgTUxYClN1cHBvcnRzOiB0ZXh0LCBzdHJlYW1pbmcsIHRvb2xfdXNlL3Rvb2xfcmVzdWx0LCBtdWx0aS1tb2RlbCByb3V0aW5nIiIiCmltcG9ydCBqc29uLCB1dWlkLCB0aW1lLCBvcwpmcm9tIGFpb2h0dHAgaW1wb3J0IHdlYiwgQ2xpZW50U2Vzc2lvbgoKIyDilIDilIAgTXVsdGktbW9kZWwgY29uZmlndXJhdGlvbiDilIDilIAKIyBFYWNoIE1MWCBzZXJ2ZXIgcnVucyBvbiBpdHMgb3duIHBvcnQuIFRoZSBwcm94eSByb3V0ZXMgYmFzZWQgb24gdGhlCiMgQW50aHJvcGljIG1vZGVsIG5hbWUgdGhhdCBDbGF1ZGUgQ29kZSBzZW5kcy4KIwojIEFkZCBtb2RlbHMgYnk6CiMgICAxLiBBZGRpbmcgYW4gZW50cnkgdG8gTU9ERUxTIGJlbG93CiMgICAyLiBTdGFydGluZyBhbiBNTFggc2VydmVyIG9uIHRoZSBzcGVjaWZpZWQgcG9ydAojICAgMy4gKE9wdGlvbmFsKSBtYXAgYWRkaXRpb25hbCBBbnRocm9waWMgbmFtZXMgaW4gTU9ERUxfUk9VVEVTCgpNT0RFTFMgPSB7CiAgICAibWFpbiI6IHsKICAgICAgICAibWx4X21vZGVsIjogb3MuZW52aXJvbi5nZXQoIk1MWF9NT0RFTF9NQUlOIiwgIm1seC1jb21tdW5pdHkvUXdlbjMuNS0xMjJCLUExMEItNGJpdCIpLAogICAgICAgICJwb3J0IjogaW50KG9zLmVudmlyb24uZ2V0KCJNTFhfUE9SVF9NQUlOIiwgIjUwMDAiKSksCiAgICAgICAgImxhYmVsIjogIlF3ZW4zLjUtMTIyQiAoZ2VuZXJhbCkiLAogICAgfSwKICAgICJmYXN0IjogewogICAgICAgICJtbHhfbW9kZWwiOiBvcy5lbnZpcm9uLmdldCgiTUxYX01PREVMX0ZBU1QiLCAibWx4LWNvbW11bml0eS9Rd2VuMy41LTM1Qi1BM0ItNGJpdCIpLAogICAgICAgICJwb3J0IjogaW50KG9zLmVudmlyb24uZ2V0KCJNTFhfUE9SVF9GQVNUIiwgIjUwMDEiKSksCiAgICAgICAgImxhYmVsIjogIlF3ZW4zLjUtMzVCLUEzQiAoZmFzdCkiLAogICAgfSwKfQoKIyBNYXAgQW50aHJvcGljIG1vZGVsIG5hbWVzIC0+IHdoaWNoIGJhY2tlbmQgdG8gdXNlCk1PREVMX1JPVVRFUyA9IHsKICAgICMgU29ubmV0L09wdXMgLT4gbWFpbiAoMTIyQikKICAgICJjbGF1ZGUtc29ubmV0LTQtNiI6ICAgICAgICAgICJtYWluIiwKICAgICJjbGF1ZGUtc29ubmV0LTQtNi0yMDI1MDUxNCI6ICJtYWluIiwKICAgICJjbGF1ZGUtb3B1cy00LTYiOiAgICAgICAgICAgICJtYWluIiwKICAgICJjbGF1ZGUtb3B1cy00LTYtMjAyNTA1MTQiOiAgICJtYWluIiwKICAgICJjbGF1ZGUtMy01LXNvbm5ldC0yMDI0MTAyMiI6ICJtYWluIiwKICAgICJjbGF1ZGUtMy01LXNvbm5ldC1sYXRlc3QiOiAgICJtYWluIiwKICAgICMgSGFpa3UgLT4gZmFzdCAoMzVCKQogICAgImNsYXVkZS1oYWlrdS00LTUtMjAyNTEwMDEiOiAgImZhc3QiLAogICAgImNsYXVkZS0zLTUtaGFpa3UtbGF0ZXN0IjogICAgImZhc3QiLAp9CgpERUZBVUxUX0JBQ0tFTkQgPSAibWFpbiIKCmRlZiBnZXRfYmFja2VuZChhbnRocm9waWNfbW9kZWwpOgogICAgIiIiUmVzb2x2ZSBBbnRocm9waWMgbW9kZWwgbmFtZSB0byBNTFggYmFja2VuZCBjb25maWciIiIKICAgIGtleSA9IE1PREVMX1JPVVRFUy5nZXQoYW50aHJvcGljX21vZGVsLCBERUZBVUxUX0JBQ0tFTkQpCiAgICBiYWNrZW5kID0gTU9ERUxTLmdldChrZXksIE1PREVMU1sibWFpbiJdKQogICAgcmV0dXJuIGJhY2tlbmQKCmRlZiBsb2cobXNnKToKICAgIHByaW50KGYiW3t0aW1lLnN0cmZ0aW1lKCclSDolTTolUycpfV0ge21zZ30iLCBmbHVzaD1UcnVlKQoKIyDilIDilIAgQW50aHJvcGljIOKGkiBPcGVuQUkgY29udmVyc2lvbiDilIDilIAKCmRlZiBjb252ZXJ0X3Rvb2xzKGFudGhyb3BpY190b29scyk6CiAgICAiIiJBbnRocm9waWMgdG9vbHMg4oaSIE9wZW5BSSB0b29scyIiIgogICAgaWYgbm90IGFudGhyb3BpY190b29sczoKICAgICAgICByZXR1cm4gTm9uZQogICAgb2FpX3Rvb2xzID0gW10KICAgIGZvciB0IGluIGFudGhyb3BpY190b29sczoKICAgICAgICBvYWlfdG9vbHMuYXBwZW5kKHsKICAgICAgICAgICAgInR5cGUiOiAiZnVuY3Rpb24iLAogICAgICAgICAgICAiZnVuY3Rpb24iOiB7CiAgICAgICAgICAgICAgICAibmFtZSI6IHRbIm5hbWUiXSwKICAgICAgICAgICAgICAgICJkZXNjcmlwdGlvbiI6IHQuZ2V0KCJkZXNjcmlwdGlvbiIsICIiKSwKICAgICAgICAgICAgICAgICJwYXJhbWV0ZXJzIjogdC5nZXQoImlucHV0X3NjaGVtYSIsIHt9KSwKICAgICAgICAgICAgfQogICAgICAgIH0pCiAgICByZXR1cm4gb2FpX3Rvb2xzCgpkZWYgY29udmVydF9tZXNzYWdlcyhtZXNzYWdlcywgc3lzdGVtPSIiKToKICAgICIiIkFudGhyb3BpYyBtZXNzYWdlcyDihpIgT3BlbkFJIG1lc3NhZ2VzIiIiCiAgICBvYWkgPSBbXQogICAgaWYgc3lzdGVtOgogICAgICAgIGlmIGlzaW5zdGFuY2Uoc3lzdGVtLCBsaXN0KToKICAgICAgICAgICAgc3lzdGVtID0gIiAiLmpvaW4oYi5nZXQoInRleHQiLCIiKSBmb3IgYiBpbiBzeXN0ZW0gaWYgYi5nZXQoInR5cGUiKT09InRleHQiKQogICAgICAgIG9haS5hcHBlbmQoeyJyb2xlIjogInN5c3RlbSIsICJjb250ZW50Ijogc3lzdGVtfSkKCiAgICBmb3IgbXNnIGluIG1lc3NhZ2VzOgogICAgICAgIHJvbGUgPSBtc2dbInJvbGUiXQogICAgICAgIGNvbnRlbnQgPSBtc2cuZ2V0KCJjb250ZW50IiwgIiIpCgogICAgICAgICMgU2ltcGxlIHN0cmluZyBjb250ZW50CiAgICAgICAgaWYgaXNpbnN0YW5jZShjb250ZW50LCBzdHIpOgogICAgICAgICAgICBvYWkuYXBwZW5kKHsicm9sZSI6IHJvbGUsICJjb250ZW50IjogY29udGVudH0pCiAgICAgICAgICAgIGNvbnRpbnVlCgogICAgICAgICMgQXJyYXkgY29udGVudCDigJQgbmVlZCB0byBzcGxpdCBpbnRvIHRleHQsIHRvb2xfdXNlLCB0b29sX3Jlc3VsdAogICAgICAgIGlmIGlzaW5zdGFuY2UoY29udGVudCwgbGlzdCk6CiAgICAgICAgICAgIHRleHRfcGFydHMgPSBbXQogICAgICAgICAgICB0b29sX2NhbGxzID0gW10KICAgICAgICAgICAgdG9vbF9yZXN1bHRzID0gW10KCiAgICAgICAgICAgIGZvciBibG9jayBpbiBjb250ZW50OgogICAgICAgICAgICAgICAgYnR5cGUgPSBibG9jay5nZXQoInR5cGUiLCAiIikKICAgICAgICAgICAgICAgIGlmIGJ0eXBlID09ICJ0ZXh0IjoKICAgICAgICAgICAgICAgICAgICB0ZXh0X3BhcnRzLmFwcGVuZChibG9jay5nZXQoInRleHQiLCAiIikpCiAgICAgICAgICAgICAgICBlbGlmIGJ0eXBlID09ICJ0b29sX3VzZSI6CiAgICAgICAgICAgICAgICAgICAgdG9vbF9jYWxscy5hcHBlbmQoewogICAgICAgICAgICAgICAgICAgICAgICAiaWQiOiBibG9ja1siaWQiXSwKICAgICAgICAgICAgICAgICAgICAgICAgInR5cGUiOiAiZnVuY3Rpb24iLAogICAgICAgICAgICAgICAgICAgICAgICAiZnVuY3Rpb24iOiB7CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAibmFtZSI6IGJsb2NrWyJuYW1lIl0sCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAiYXJndW1lbnRzIjoganNvbi5kdW1wcyhibG9jay5nZXQoImlucHV0Iiwge30pKSwKICAgICAgICAgICAgICAgICAgICAgICAgfQogICAgICAgICAgICAgICAgICAgIH0pCiAgICAgICAgICAgICAgICBlbGlmIGJ0eXBlID09ICJ0b29sX3Jlc3VsdCI6CiAgICAgICAgICAgICAgICAgICAgIyBFeHRyYWN0IHRleHQgZnJvbSB0b29sX3Jlc3VsdCBjb250ZW50CiAgICAgICAgICAgICAgICAgICAgdHJfY29udGVudCA9IGJsb2NrLmdldCgiY29udGVudCIsICIiKQogICAgICAgICAgICAgICAgICAgIGlmIGlzaW5zdGFuY2UodHJfY29udGVudCwgbGlzdCk6CiAgICAgICAgICAgICAgICAgICAgICAgIHRyX2NvbnRlbnQgPSAiXG4iLmpvaW4oCiAgICAgICAgICAgICAgICAgICAgICAgICAgICBiLmdldCgidGV4dCIsIiIpIGZvciBiIGluIHRyX2NvbnRlbnQKICAgICAgICAgICAgICAgICAgICAgICAgICAgIGlmIGlzaW5zdGFuY2UoYiwgZGljdCkgYW5kIGIuZ2V0KCJ0eXBlIikgPT0gInRleHQiCiAgICAgICAgICAgICAgICAgICAgICAgICkKICAgICAgICAgICAgICAgICAgICBlbGlmIG5vdCBpc2luc3RhbmNlKHRyX2NvbnRlbnQsIHN0cik6CiAgICAgICAgICAgICAgICAgICAgICAgIHRyX2NvbnRlbnQgPSBzdHIodHJfY29udGVudCkKICAgICAgICAgICAgICAgICAgICB0b29sX3Jlc3VsdHMuYXBwZW5kKHsKICAgICAgICAgICAgICAgICAgICAgICAgInJvbGUiOiAidG9vbCIsCiAgICAgICAgICAgICAgICAgICAgICAgICJ0b29sX2NhbGxfaWQiOiBibG9ja1sidG9vbF91c2VfaWQiXSwKICAgICAgICAgICAgICAgICAgICAgICAgImNvbnRlbnQiOiB0cl9jb250ZW50LAogICAgICAgICAgICAgICAgICAgIH0pCgogICAgICAgICAgICBpZiByb2xlID09ICJhc3Npc3RhbnQiOgogICAgICAgICAgICAgICAgbSA9IHsicm9sZSI6ICJhc3Npc3RhbnQifQogICAgICAgICAgICAgICAgaWYgdGV4dF9wYXJ0czoKICAgICAgICAgICAgICAgICAgICBtWyJjb250ZW50Il0gPSAiXG4iLmpvaW4odGV4dF9wYXJ0cykKICAgICAgICAgICAgICAgIGVsc2U6CiAgICAgICAgICAgICAgICAgICAgbVsiY29udGVudCJdID0gIiIKICAgICAgICAgICAgICAgIGlmIHRvb2xfY2FsbHM6CiAgICAgICAgICAgICAgICAgICAgbVsidG9vbF9jYWxscyJdID0gdG9vbF9jYWxscwogICAgICAgICAgICAgICAgb2FpLmFwcGVuZChtKQogICAgICAgICAgICBlbGlmIHJvbGUgPT0gInVzZXIiOgogICAgICAgICAgICAgICAgIyBVc2VyIG1lc3NhZ2VzIG1heSBjb250YWluIHRleHQgKyB0b29sX3Jlc3VsdHMKICAgICAgICAgICAgICAgIGlmIHRleHRfcGFydHM6CiAgICAgICAgICAgICAgICAgICAgb2FpLmFwcGVuZCh7InJvbGUiOiAidXNlciIsICJjb250ZW50IjogIlxuIi5qb2luKHRleHRfcGFydHMpfSkKICAgICAgICAgICAgICAgIGZvciB0ciBpbiB0b29sX3Jlc3VsdHM6CiAgICAgICAgICAgICAgICAgICAgb2FpLmFwcGVuZCh0cikKICAgICAgICAgICAgZWxzZToKICAgICAgICAgICAgICAgIG9haS5hcHBlbmQoeyJyb2xlIjogcm9sZSwgImNvbnRlbnQiOiBzdHIoY29udGVudCl9KQoKICAgIHJldHVybiBvYWkKCiMg4pSA4pSAIE9wZW5BSSDihpIgQW50aHJvcGljIGNvbnZlcnNpb24g4pSA4pSACgpkZWYgb2FpX3Jlc3BvbnNlX3RvX2FudGhyb3BpYyhkYXRhLCBtb2RlbCk6CiAgICAiIiJDb252ZXJ0IE9wZW5BSSBjb21wbGV0aW9uIHJlc3BvbnNlIHRvIEFudGhyb3BpYyBtZXNzYWdlIHJlc3BvbnNlIiIiCiAgICBjaG9pY2UgPSBkYXRhLmdldCgiY2hvaWNlcyIsIFt7fV0pWzBdCiAgICBtZXNzYWdlID0gY2hvaWNlLmdldCgibWVzc2FnZSIsIHt9KQogICAgdXNhZ2UgPSBkYXRhLmdldCgidXNhZ2UiLCB7fSkKICAgIGZpbmlzaCA9IGNob2ljZS5nZXQoImZpbmlzaF9yZWFzb24iLCAic3RvcCIpCgogICAgY29udGVudF9ibG9ja3MgPSBbXQoKICAgICMgVGV4dCBjb250ZW50CiAgICB0ZXh0ID0gbWVzc2FnZS5nZXQoImNvbnRlbnQiLCAiIikKICAgIGlmIHRleHQ6CiAgICAgICAgY29udGVudF9ibG9ja3MuYXBwZW5kKHsidHlwZSI6ICJ0ZXh0IiwgInRleHQiOiB0ZXh0fSkKCiAgICAjIFRvb2wgY2FsbHMKICAgIGZvciB0YyBpbiBtZXNzYWdlLmdldCgidG9vbF9jYWxscyIsIFtdKToKICAgICAgICBmdW5jID0gdGMuZ2V0KCJmdW5jdGlvbiIsIHt9KQogICAgICAgIHRyeToKICAgICAgICAgICAgaW5wdXRfZGF0YSA9IGpzb24ubG9hZHMoZnVuYy5nZXQoImFyZ3VtZW50cyIsICJ7fSIpKQogICAgICAgIGV4Y2VwdCBqc29uLkpTT05EZWNvZGVFcnJvcjoKICAgICAgICAgICAgaW5wdXRfZGF0YSA9IHt9CiAgICAgICAgY29udGVudF9ibG9ja3MuYXBwZW5kKHsKICAgICAgICAgICAgInR5cGUiOiAidG9vbF91c2UiLAogICAgICAgICAgICAiaWQiOiBmInRvb2x1X3t1dWlkLnV1aWQ0KCkuaGV4WzoyNF19IiwKICAgICAgICAgICAgIm5hbWUiOiBmdW5jLmdldCgibmFtZSIsICIiKSwKICAgICAgICAgICAgImlucHV0IjogaW5wdXRfZGF0YSwKICAgICAgICB9KQoKICAgICMgRGV0ZXJtaW5lIHN0b3AgcmVhc29uCiAgICBpZiBmaW5pc2ggPT0gInRvb2xfY2FsbHMiOgogICAgICAgIHN0b3BfcmVhc29uID0gInRvb2xfdXNlIgogICAgZWxzZToKICAgICAgICBzdG9wX3JlYXNvbiA9ICJlbmRfdHVybiIKCiAgICByZXR1cm4gewogICAgICAgICJpZCI6IGYibXNnX3t1dWlkLnV1aWQ0KCkuaGV4WzoyNF19IiwKICAgICAgICAidHlwZSI6ICJtZXNzYWdlIiwKICAgICAgICAicm9sZSI6ICJhc3Npc3RhbnQiLAogICAgICAgICJtb2RlbCI6IG1vZGVsLAogICAgICAgICJjb250ZW50IjogY29udGVudF9ibG9ja3MgaWYgY29udGVudF9ibG9ja3MgZWxzZSBbeyJ0eXBlIjogInRleHQiLCAidGV4dCI6ICIifV0sCiAgICAgICAgInN0b3BfcmVhc29uIjogc3RvcF9yZWFzb24sCiAgICAgICAgInN0b3Bfc2VxdWVuY2UiOiBOb25lLAogICAgICAgICJ1c2FnZSI6IHsKICAgICAgICAgICAgImlucHV0X3Rva2VucyI6IHVzYWdlLmdldCgicHJvbXB0X3Rva2VucyIsIDApLAogICAgICAgICAgICAib3V0cHV0X3Rva2VucyI6IHVzYWdlLmdldCgiY29tcGxldGlvbl90b2tlbnMiLCAwKSwKICAgICAgICAgICAgImNhY2hlX2NyZWF0aW9uX2lucHV0X3Rva2VucyI6IDAsCiAgICAgICAgICAgICJjYWNoZV9yZWFkX2lucHV0X3Rva2VucyI6IDAsCiAgICAgICAgfQogICAgfQoKIyDilIDilIAgSGFuZGxlcnMg4pSA4pSACgphc3luYyBkZWYgaGFuZGxlX21lc3NhZ2VzKHJlcXVlc3QpOgogICAgYm9keSA9IGF3YWl0IHJlcXVlc3QuanNvbigpCiAgICBtb2RlbCA9IGJvZHkuZ2V0KCJtb2RlbCIsICJjbGF1ZGUtc29ubmV0LTQtNiIpCiAgICBzdHJlYW0gPSBib2R5LmdldCgic3RyZWFtIiwgRmFsc2UpCiAgICB0b29scyA9IGJvZHkuZ2V0KCJ0b29scyIsIE5vbmUpCiAgICBiYWNrZW5kID0gZ2V0X2JhY2tlbmQobW9kZWwpCiAgICBtbHhfdXJsID0gZiJodHRwOi8vMTI3LjAuMC4xOntiYWNrZW5kWydwb3J0J119L3YxL2NoYXQvY29tcGxldGlvbnMiCiAgICBsb2coZiJQT1NUIC92MS9tZXNzYWdlcyBtb2RlbD17bW9kZWx9IC0+IHtiYWNrZW5kWydsYWJlbCddfSA6e2JhY2tlbmRbJ3BvcnQnXX0gc3RyZWFtPXtzdHJlYW19IHRvb2xzPXtsZW4odG9vbHMpIGlmIHRvb2xzIGVsc2UgMH0iKQoKICAgIG9haV9ib2R5ID0gewogICAgICAgICJtb2RlbCI6IGJhY2tlbmRbIm1seF9tb2RlbCJdLAogICAgICAgICJtZXNzYWdlcyI6IGNvbnZlcnRfbWVzc2FnZXMoYm9keS5nZXQoIm1lc3NhZ2VzIiwgW10pLCBib2R5LmdldCgic3lzdGVtIiwgIiIpKSwKICAgICAgICAibWF4X3Rva2VucyI6IGJvZHkuZ2V0KCJtYXhfdG9rZW5zIiwgNDA5NiksCiAgICAgICAgImNoYXRfdGVtcGxhdGVfa3dhcmdzIjogeyJlbmFibGVfdGhpbmtpbmciOiBGYWxzZX0sCiAgICB9CiAgICBpZiBib2R5LmdldCgidGVtcGVyYXR1cmUiKSBpcyBub3QgTm9uZToKICAgICAgICBvYWlfYm9keVsidGVtcGVyYXR1cmUiXSA9IGJvZHlbInRlbXBlcmF0dXJlIl0KICAgIGlmIHRvb2xzOgogICAgICAgIG9haV9ib2R5WyJ0b29scyJdID0gY29udmVydF90b29scyh0b29scykKCiAgICBpZiBzdHJlYW06CiAgICAgICAgcmV0dXJuIGF3YWl0IGhhbmRsZV9zdHJlYW0ocmVxdWVzdCwgb2FpX2JvZHksIG1vZGVsLCBtbHhfdXJsKQoKICAgICMgTm9uLXN0cmVhbWluZwogICAgYXN5bmMgd2l0aCBDbGllbnRTZXNzaW9uKCkgYXMgc2Vzc2lvbjoKICAgICAgICBhc3luYyB3aXRoIHNlc3Npb24ucG9zdChtbHhfdXJsLCBqc29uPW9haV9ib2R5KSBhcyByZXNwOgogICAgICAgICAgICBkYXRhID0gYXdhaXQgcmVzcC5qc29uKCkKCiAgICByZXR1cm4gd2ViLmpzb25fcmVzcG9uc2Uob2FpX3Jlc3BvbnNlX3RvX2FudGhyb3BpYyhkYXRhLCBtb2RlbCkpCgphc3luYyBkZWYgaGFuZGxlX3N0cmVhbShyZXF1ZXN0LCBvYWlfYm9keSwgbW9kZWwsIG1seF91cmwpOgogICAgbXNnX2lkID0gZiJtc2dfe3V1aWQudXVpZDQoKS5oZXhbOjI0XX0iCiAgICByZXNwb25zZSA9IHdlYi5TdHJlYW1SZXNwb25zZSgpCiAgICByZXNwb25zZS5oZWFkZXJzWyJDb250ZW50LVR5cGUiXSA9ICJ0ZXh0L2V2ZW50LXN0cmVhbSIKICAgIHJlc3BvbnNlLmhlYWRlcnNbIkNhY2hlLUNvbnRyb2wiXSA9ICJuby1jYWNoZSIKICAgIGF3YWl0IHJlc3BvbnNlLnByZXBhcmUocmVxdWVzdCkKCiAgICBhc3luYyBkZWYgc2VuZChldmVudF90eXBlLCBkYXRhKToKICAgICAgICBhd2FpdCByZXNwb25zZS53cml0ZShmImV2ZW50OiB7ZXZlbnRfdHlwZX1cbmRhdGE6IHtqc29uLmR1bXBzKGRhdGEpfVxuXG4iLmVuY29kZSgpKQoKICAgICMgbWVzc2FnZV9zdGFydAogICAgYXdhaXQgc2VuZCgibWVzc2FnZV9zdGFydCIsIHsKICAgICAgICAidHlwZSI6ICJtZXNzYWdlX3N0YXJ0IiwKICAgICAgICAibWVzc2FnZSI6IHsKICAgICAgICAgICAgImlkIjogbXNnX2lkLCAidHlwZSI6ICJtZXNzYWdlIiwgInJvbGUiOiAiYXNzaXN0YW50IiwKICAgICAgICAgICAgIm1vZGVsIjogbW9kZWwsICJjb250ZW50IjogW10sICJzdG9wX3JlYXNvbiI6IE5vbmUsICJzdG9wX3NlcXVlbmNlIjogTm9uZSwKICAgICAgICAgICAgInVzYWdlIjogeyJpbnB1dF90b2tlbnMiOiAwLCAib3V0cHV0X3Rva2VucyI6IDAsCiAgICAgICAgICAgICAgICAgICAgICAiY2FjaGVfY3JlYXRpb25faW5wdXRfdG9rZW5zIjogMCwgImNhY2hlX3JlYWRfaW5wdXRfdG9rZW5zIjogMH0KICAgICAgICB9CiAgICB9KQoKICAgIG9haV9ib2R5WyJzdHJlYW0iXSA9IFRydWUKICAgIGZ1bGxfdGV4dCA9ICIiCiAgICAjIFRyYWNrIHRvb2wgY2FsbHMgYmVpbmcgc3RyZWFtZWQ6IHtpbmRleDoge2lkLCBuYW1lLCBhcmd1bWVudHN9fQogICAgdG9vbF9jYWxscyA9IHt9CiAgICBjb250ZW50X2luZGV4ID0gMCAgIyBOZXh0IEFudGhyb3BpYyBjb250ZW50IGJsb2NrIGluZGV4CiAgICB0ZXh0X2Jsb2NrX3N0YXJ0ZWQgPSBGYWxzZQogICAgdG9vbF9ibG9ja3Nfc3RhcnRlZCA9IHt9ICAjIGluZGV4IC0+IGJvb2wKCiAgICBhc3luYyB3aXRoIENsaWVudFNlc3Npb24oKSBhcyBzZXNzaW9uOgogICAgICAgIGFzeW5jIHdpdGggc2Vzc2lvbi5wb3N0KG1seF91cmwsIGpzb249b2FpX2JvZHkpIGFzIHJlc3A6CiAgICAgICAgICAgIGFzeW5jIGZvciBsaW5lIGluIHJlc3AuY29udGVudDoKICAgICAgICAgICAgICAgIGxpbmUgPSBsaW5lLmRlY29kZSgpLnN0cmlwKCkKICAgICAgICAgICAgICAgIGlmIG5vdCBsaW5lLnN0YXJ0c3dpdGgoImRhdGE6ICIpOgogICAgICAgICAgICAgICAgICAgIGNvbnRpbnVlCiAgICAgICAgICAgICAgICBkYXRhX3N0ciA9IGxpbmVbNjpdCiAgICAgICAgICAgICAgICBpZiBkYXRhX3N0ciA9PSAiW0RPTkVdIjoKICAgICAgICAgICAgICAgICAgICBicmVhawogICAgICAgICAgICAgICAgdHJ5OgogICAgICAgICAgICAgICAgICAgIGNodW5rID0ganNvbi5sb2FkcyhkYXRhX3N0cikKICAgICAgICAgICAgICAgICAgICBkZWx0YSA9IGNodW5rLmdldCgiY2hvaWNlcyIsIFt7fV0pWzBdLmdldCgiZGVsdGEiLCB7fSkKCiAgICAgICAgICAgICAgICAgICAgIyBUZXh0IGNvbnRlbnQKICAgICAgICAgICAgICAgICAgICB0ZXh0ID0gZGVsdGEuZ2V0KCJjb250ZW50IiwgIiIpCiAgICAgICAgICAgICAgICAgICAgaWYgdGV4dDoKICAgICAgICAgICAgICAgICAgICAgICAgaWYgbm90IHRleHRfYmxvY2tfc3RhcnRlZDoKICAgICAgICAgICAgICAgICAgICAgICAgICAgIGF3YWl0IHNlbmQoImNvbnRlbnRfYmxvY2tfc3RhcnQiLCB7CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgInR5cGUiOiAiY29udGVudF9ibG9ja19zdGFydCIsCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgImluZGV4IjogY29udGVudF9pbmRleCwKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAiY29udGVudF9ibG9jayI6IHsidHlwZSI6ICJ0ZXh0IiwgInRleHQiOiAiIn0KICAgICAgICAgICAgICAgICAgICAgICAgICAgIH0pCiAgICAgICAgICAgICAgICAgICAgICAgICAgICB0ZXh0X2Jsb2NrX3N0YXJ0ZWQgPSBUcnVlCiAgICAgICAgICAgICAgICAgICAgICAgIGZ1bGxfdGV4dCArPSB0ZXh0CiAgICAgICAgICAgICAgICAgICAgICAgIGF3YWl0IHNlbmQoImNvbnRlbnRfYmxvY2tfZGVsdGEiLCB7CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAidHlwZSI6ICJjb250ZW50X2Jsb2NrX2RlbHRhIiwKICAgICAgICAgICAgICAgICAgICAgICAgICAgICJpbmRleCI6IGNvbnRlbnRfaW5kZXgsCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAiZGVsdGEiOiB7InR5cGUiOiAidGV4dF9kZWx0YSIsICJ0ZXh0IjogdGV4dH0KICAgICAgICAgICAgICAgICAgICAgICAgfSkKCiAgICAgICAgICAgICAgICAgICAgIyBUb29sIGNhbGxzCiAgICAgICAgICAgICAgICAgICAgZm9yIHRjIGluIGRlbHRhLmdldCgidG9vbF9jYWxscyIsIFtdKToKICAgICAgICAgICAgICAgICAgICAgICAgaWR4ID0gdGMuZ2V0KCJpbmRleCIsIDApCiAgICAgICAgICAgICAgICAgICAgICAgIGlmIGlkeCBub3QgaW4gdG9vbF9jYWxsczoKICAgICAgICAgICAgICAgICAgICAgICAgICAgIHRvb2xfY2FsbHNbaWR4XSA9IHsKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAiaWQiOiB0Yy5nZXQoImlkIiwgZiJ0b29sdV97dXVpZC51dWlkNCgpLmhleFs6MjRdfSIpLAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICJuYW1lIjogdGMuZ2V0KCJmdW5jdGlvbiIsIHt9KS5nZXQoIm5hbWUiLCAiIiksCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgImFyZ3VtZW50cyI6ICIiLAogICAgICAgICAgICAgICAgICAgICAgICAgICAgfQogICAgICAgICAgICAgICAgICAgICAgICBlbHNlOgogICAgICAgICAgICAgICAgICAgICAgICAgICAgIyBBY2N1bXVsYXRlIGFyZ3VtZW50cwogICAgICAgICAgICAgICAgICAgICAgICAgICAgdG9vbF9jYWxsc1tpZHhdWyJhcmd1bWVudHMiXSArPSB0Yy5nZXQoImZ1bmN0aW9uIiwge30pLmdldCgiYXJndW1lbnRzIiwgIiIpCgogICAgICAgICAgICAgICAgICAgICAgICBmdW5jID0gdGMuZ2V0KCJmdW5jdGlvbiIsIHt9KQogICAgICAgICAgICAgICAgICAgICAgICBpZiBmdW5jLmdldCgibmFtZSIpIGFuZCBpZHggbm90IGluIHRvb2xfYmxvY2tzX3N0YXJ0ZWQ6CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAjIENsb3NlIHRleHQgYmxvY2sgaWYgb3BlbgogICAgICAgICAgICAgICAgICAgICAgICAgICAgaWYgdGV4dF9ibG9ja19zdGFydGVkOgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIGF3YWl0IHNlbmQoImNvbnRlbnRfYmxvY2tfc3RvcCIsIHsKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgInR5cGUiOiAiY29udGVudF9ibG9ja19zdG9wIiwKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgImluZGV4IjogY29udGVudF9pbmRleAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIH0pCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgY29udGVudF9pbmRleCArPSAxCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgdGV4dF9ibG9ja19zdGFydGVkID0gRmFsc2UKCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAjIFN0YXJ0IHRvb2xfdXNlIGJsb2NrCiAgICAgICAgICAgICAgICAgICAgICAgICAgICB0b29sX2Jsb2Nrc19zdGFydGVkW2lkeF0gPSBjb250ZW50X2luZGV4CiAgICAgICAgICAgICAgICAgICAgICAgICAgICBhd2FpdCBzZW5kKCJjb250ZW50X2Jsb2NrX3N0YXJ0IiwgewogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICJ0eXBlIjogImNvbnRlbnRfYmxvY2tfc3RhcnQiLAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICJpbmRleCI6IGNvbnRlbnRfaW5kZXgsCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgImNvbnRlbnRfYmxvY2siOiB7CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICJ0eXBlIjogInRvb2xfdXNlIiwKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgImlkIjogZiJ0b29sdV97dXVpZC51dWlkNCgpLmhleFs6MjRdfSIsCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICJuYW1lIjogZnVuY1sibmFtZSJdLAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAiaW5wdXQiOiB7fQogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIH0KICAgICAgICAgICAgICAgICAgICAgICAgICAgIH0pCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAjIFN0b3JlIHRoZSB0b29sdV9pZCBmb3IgdGhpcyBibG9jawogICAgICAgICAgICAgICAgICAgICAgICAgICAgdG9vbF9jYWxsc1tpZHhdWyJibG9ja19pbmRleCJdID0gY29udGVudF9pbmRleAogICAgICAgICAgICAgICAgICAgICAgICAgICAgY29udGVudF9pbmRleCArPSAxCgogICAgICAgICAgICAgICAgICAgICAgICBpZiBmdW5jLmdldCgiYXJndW1lbnRzIik6CiAgICAgICAgICAgICAgICAgICAgICAgICAgICBibG9ja19pZHggPSB0b29sX2NhbGxzW2lkeF0uZ2V0KCJibG9ja19pbmRleCIsIGNvbnRlbnRfaW5kZXggLSAxKQogICAgICAgICAgICAgICAgICAgICAgICAgICAgYXdhaXQgc2VuZCgiY29udGVudF9ibG9ja19kZWx0YSIsIHsKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAidHlwZSI6ICJjb250ZW50X2Jsb2NrX2RlbHRhIiwKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAiaW5kZXgiOiBibG9ja19pZHgsCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgImRlbHRhIjogewogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAidHlwZSI6ICJpbnB1dF9qc29uX2RlbHRhIiwKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgInBhcnRpYWxfanNvbiI6IGZ1bmNbImFyZ3VtZW50cyJdCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgfQogICAgICAgICAgICAgICAgICAgICAgICAgICAgfSkKICAgICAgICAgICAgICAgIGV4Y2VwdCBFeGNlcHRpb24gYXMgZToKICAgICAgICAgICAgICAgICAgICBsb2coZiJTdHJlYW0gcGFyc2UgZXJyb3I6IHtlfSIpCgogICAgIyBDbG9zZSBvcGVuIGJsb2NrcwogICAgaWYgdGV4dF9ibG9ja19zdGFydGVkOgogICAgICAgIGF3YWl0IHNlbmQoImNvbnRlbnRfYmxvY2tfc3RvcCIsIHsidHlwZSI6ICJjb250ZW50X2Jsb2NrX3N0b3AiLCAiaW5kZXgiOiAwfSkKCiAgICBmb3IgaWR4LCB0YyBpbiB0b29sX2NhbGxzLml0ZW1zKCk6CiAgICAgICAgYmxvY2tfaWR4ID0gdGMuZ2V0KCJibG9ja19pbmRleCIsIGlkeCArIDEpCiAgICAgICAgYXdhaXQgc2VuZCgiY29udGVudF9ibG9ja19zdG9wIiwgeyJ0eXBlIjogImNvbnRlbnRfYmxvY2tfc3RvcCIsICJpbmRleCI6IGJsb2NrX2lkeH0pCgogICAgIyBEZXRlcm1pbmUgc3RvcCByZWFzb24KICAgIHN0b3BfcmVhc29uID0gInRvb2xfdXNlIiBpZiB0b29sX2NhbGxzIGVsc2UgImVuZF90dXJuIgoKICAgIGF3YWl0IHNlbmQoIm1lc3NhZ2VfZGVsdGEiLCB7CiAgICAgICAgInR5cGUiOiAibWVzc2FnZV9kZWx0YSIsCiAgICAgICAgImRlbHRhIjogeyJzdG9wX3JlYXNvbiI6IHN0b3BfcmVhc29uLCAic3RvcF9zZXF1ZW5jZSI6IE5vbmV9LAogICAgICAgICJ1c2FnZSI6IHsib3V0cHV0X3Rva2VucyI6IGxlbihmdWxsX3RleHQpIC8vIDQgKyBzdW0obGVuKHRjWyJhcmd1bWVudHMiXSkgLy8gNCBmb3IgdGMgaW4gdG9vbF9jYWxscy52YWx1ZXMoKSl9CiAgICB9KQogICAgYXdhaXQgc2VuZCgibWVzc2FnZV9zdG9wIiwgeyJ0eXBlIjogIm1lc3NhZ2Vfc3RvcCJ9KQoKICAgIGF3YWl0IHJlc3BvbnNlLndyaXRlX2VvZigpCiAgICByZXR1cm4gcmVzcG9uc2UKCmFzeW5jIGRlZiBoYW5kbGVfY291bnRfdG9rZW5zKHJlcXVlc3QpOgogICAgYm9keSA9IGF3YWl0IHJlcXVlc3QuanNvbigpCiAgICBsb2coZiJQT1NUIC92MS9tZXNzYWdlcy9jb3VudF90b2tlbnMiKQogICAgbXNncyA9IGNvbnZlcnRfbWVzc2FnZXMoYm9keS5nZXQoIm1lc3NhZ2VzIiwgW10pLCBib2R5LmdldCgic3lzdGVtIiwgIiIpKQogICAgdG90YWwgPSBzdW0obGVuKG0uZ2V0KCJjb250ZW50IiwgIiIpKSAvLyA0IGZvciBtIGluIG1zZ3MpCiAgICByZXR1cm4gd2ViLmpzb25fcmVzcG9uc2UoeyJpbnB1dF90b2tlbnMiOiB0b3RhbH0pCgphc3luYyBkZWYgaGFuZGxlX21vZGVscyhyZXF1ZXN0KToKICAgIGxvZyhmIkdFVCAvdjEvbW9kZWxzIikKICAgIHJldHVybiB3ZWIuanNvbl9yZXNwb25zZSh7CiAgICAgICAgImRhdGEiOiBbeyJpZCI6IG0sICJvYmplY3QiOiAibW9kZWwiLCAiY3JlYXRlZCI6IDE2Nzc2MTA2MDIsICJvd25lZF9ieSI6ICJhbnRocm9waWMifQogICAgICAgICAgICAgICAgIGZvciBtIGluIE1PREVMX1JPVVRFUy5rZXlzKCldLAogICAgICAgICJvYmplY3QiOiAibGlzdCIKICAgIH0pCgphc3luYyBkZWYgY2F0Y2hfYWxsKHJlcXVlc3QpOgogICAgYm9keSA9IGF3YWl0IHJlcXVlc3QudGV4dCgpCiAgICBsb2coZiJDQVRDSC1BTEwge3JlcXVlc3QubWV0aG9kfSB7cmVxdWVzdC5wYXRofSBib2R5PXtib2R5WzozMDBdfSIpCiAgICByZXR1cm4gd2ViLmpzb25fcmVzcG9uc2UoeyJvayI6IFRydWV9KQoKYXBwID0gd2ViLkFwcGxpY2F0aW9uKCkKYXBwLnJvdXRlci5hZGRfcG9zdCgiL3YxL21lc3NhZ2VzL2NvdW50X3Rva2VucyIsIGhhbmRsZV9jb3VudF90b2tlbnMpCmFwcC5yb3V0ZXIuYWRkX3Bvc3QoIi92MS9tZXNzYWdlcyIsIGhhbmRsZV9tZXNzYWdlcykKYXBwLnJvdXRlci5hZGRfZ2V0KCIvdjEvbW9kZWxzIiwgaGFuZGxlX21vZGVscykKYXBwLnJvdXRlci5hZGRfcm91dGUoIioiLCAiL3twYXRoOi4qfSIsIGNhdGNoX2FsbCkKCmlmIF9fbmFtZV9fID09ICJfX21haW5fXyI6CiAgICBmb3IgbmFtZSwgY2ZnIGluIE1PREVMUy5pdGVtcygpOgogICAgICAgIGxvZyhmIiAgW3tuYW1lfV0ge2NmZ1snbWx4X21vZGVsJ119IC0+IDp7Y2ZnWydwb3J0J119ICh7Y2ZnWydsYWJlbCddfSkiKQogICAgbG9nKGYiQW50aHJvcGljIHByb3h5IG9uIDo0MDAxIChtdWx0aS1tb2RlbCwgdG9vbF91c2UpIikKICAgIHdlYi5ydW5fYXBwKGFwcCwgaG9zdD0iMC4wLjAuMCIsIHBvcnQ9NDAwMSwgcHJpbnQ9bGFtYmRhIHg6IGxvZyh4KSkK
B64EOF

# -------------------------------------------------------
# 5. ai.sh (start/stop/status/test)
# -------------------------------------------------------
echo "[5/6] Writing ~/ai.sh..."
cat > "$HOME/ai.sh" << 'SHEOF'
#!/bin/bash
# Multi-model MLX server manager
MODEL_MAIN="mlx-community/Qwen3.5-122B-A10B-4bit"
MODEL_FAST="mlx-community/Qwen3.5-35B-A3B-4bit"
PORT_MAIN=5000
PORT_FAST=5001
PROXY_PORT=4001
VENV=~/mlx_env/bin/activate

start_model() {
  local model=$1 port=$2 label=$3 logfile=$4
  if curl -s http://127.0.0.1:$port/v1/models 2>/dev/null | grep -q "model"; then
    echo "  $label: already running (:$port)"
    return 0
  fi
  echo "  $label starting (:$port)..."
  nohup mlx_lm.server --model "$model" --port $port > ~/$logfile 2>&1 &
  for i in $(seq 1 40); do
    curl -s http://127.0.0.1:$port/v1/models 2>/dev/null | grep -q "model" && break
    [ $i -eq 40 ] && { echo "  $label: TIMEOUT"; return 1; }
    sleep 3
  done
  echo "  $label: ready"
}

start() {
  if pgrep -f "anthropic_proxy" > /dev/null; then
    echo "Already running. ~/ai.sh status"
    return 1
  fi
  source "$VENV"

  echo "Starting MLX servers..."
  start_model "$MODEL_MAIN" $PORT_MAIN "main (122B)" "mlx_main.log"

  # Fast model is optional — start in background, don't block
  start_model "$MODEL_FAST" $PORT_FAST "fast (35B)" "mlx_fast.log" &

  echo "Proxy starting..."
  nohup python3 ~/anthropic_proxy.py > ~/proxy.log 2>&1 &
  sleep 2

  IP=$(ipconfig getifaddr en0 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}')
  echo ""
  echo "========================================"
  echo " Ready!"
  echo " Sonnet/Opus -> $MODEL_MAIN (:$PORT_MAIN)"
  echo " Haiku       -> $MODEL_FAST (:$PORT_FAST)"
  echo " Proxy       -> http://$IP:$PROXY_PORT"
  echo "========================================"
  echo " cld  -> Claude Code (local)"
  echo " clc  -> Claude Code (Anthropic cloud)"
  echo "========================================"
}

stop() {
  pkill -f "mlx_lm.server" 2>/dev/null
  pkill -f "anthropic_proxy" 2>/dev/null
  echo "Stopped"
}

status() {
  echo "=== Models ==="
  curl -s http://127.0.0.1:$PORT_MAIN/v1/models 2>/dev/null | grep -q model \
    && echo "main (122B): running (:$PORT_MAIN)" || echo "main (122B): stopped"
  curl -s http://127.0.0.1:$PORT_FAST/v1/models 2>/dev/null | grep -q model \
    && echo "fast (35B):  running (:$PORT_FAST)" || echo "fast (35B):  stopped"
  echo "=== Proxy ==="
  pgrep -f "anthropic_proxy" > /dev/null \
    && echo "Proxy: running (:$PROXY_PORT)" || echo "Proxy: stopped"
}

test_it() {
  for m in claude-sonnet-4-6 claude-haiku-4-5-20251001; do
    R=$(curl -s http://127.0.0.1:$PROXY_PORT/v1/messages \
      -H "Content-Type: application/json" \
      -H "x-api-key: dummy" \
      -H "anthropic-version: 2023-06-01" \
      -d "{\"model\":\"$m\",\"messages\":[{\"role\":\"user\",\"content\":\"1+1=?\"}],\"max_tokens\":20}")
    C=$(echo "$R" | python3 -c 'import sys,json;print(json.load(sys.stdin)["content"][0]["text"])' 2>/dev/null)
    [ -n "$C" ] && echo "$m -> OK: $C" || echo "$m -> Error"
  done
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
