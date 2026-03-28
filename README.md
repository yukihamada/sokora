# Local Claude Code with MLX

Apple Silicon Mac で Claude Code をローカル実行。API費用ゼロ、ツール実行対応、完全オフライン動作。

> Qwen3.5-122B を MLX で動かし、Anthropic API互換プロキシ経由で Claude Code がそのまま使える

## 仕組み

```
                                          ┌─ MLX :5000 → Qwen3.5-122B (Sonnet/Opus)
Claude Code  →  Anthropic Proxy (:4001) ──┤
  (tool_use)     (自動モデル振り分け)       └─ MLX :5001 → Qwen3.5-35B  (Haiku/高速)
```

Claude Code は本家 Anthropic API と同じプロトコルで通信。プロキシがモデル名を見て自動的に振り分ける:

| Claude Code が送るモデル名 | 振り分け先 | 用途 |
|---------------------------|-----------|------|
| `claude-sonnet-4-6` | Qwen3.5-122B (:5000) | 汎用・高品質 |
| `claude-opus-4-6` | Qwen3.5-122B (:5000) | 汎用・高品質 |
| `claude-haiku-4-5` | Qwen3.5-35B-A3B (:5001) | 高速・軽量 |

## 必要なもの

- Apple Silicon Mac（M1/M2/M3/M4/M5）64GB以上（128GB推奨）
- macOS 14+
- ディスク空き ~40GB（モデルデータ）

## セットアップ（1コマンド）

```bash
bash setup.sh
```

これだけで以下が全自動で入る:
- Homebrew + Python 3.11
- MLX-LM（Apple GPU推論エンジン）
- Qwen3.5-122B-A10B-4bit モデル
- Anthropic互換プロキシ
- 起動/停止スクリプト
- Claude Code設定（settings.json）
- シェルエイリアス

### リモートマシンにセットアップ

```bash
ssh user@mac-ip "bash -s" < setup.sh
```

## 使い方

```bash
# AIサーバー起動
~/ai.sh start

# ローカルAIでClaude Code起動
cld

# 本家Anthropicに切り替え
clc
```

## コマンド一覧

| コマンド | 説明 |
|---------|------|
| `~/ai.sh start` | MLX + プロキシ起動 |
| `~/ai.sh stop` | 全停止 |
| `~/ai.sh status` | 稼働状況を確認 |
| `~/ai.sh test` | 推論テスト |
| `~/ai.sh restart` | 再起動 |
| `cld` | ローカルAIで Claude Code |
| `clc` | 本家 Anthropic で Claude Code |
| `ai-local` | ローカルに切替（起動しない） |
| `ai-cloud` | クラウドに切替（起動しない） |

## アーキテクチャ

### Anthropic Proxy (`anthropic_proxy.py`)

Anthropic Messages API と OpenAI Chat Completions API を相互変換する軽量プロキシ（aiohttp）。

**エンドポイント:**
- `POST /v1/messages` — チャット（ストリーミング対応）
- `POST /v1/messages/count_tokens` — トークン数カウント
- `GET /v1/models` — モデル一覧

**tool_use 変換テーブル:**

| Anthropic 形式 | OpenAI 形式 |
|---------------|------------|
| `tools[].input_schema` | `tools[].function.parameters` |
| `content[].type: "tool_use"` | `message.tool_calls[]` |
| `content[].type: "tool_result"` | `role: "tool"` メッセージ |
| `stop_reason: "tool_use"` | `finish_reason: "tool_calls"` |

### MLX Server

`mlx-lm` で Apple GPU を使ってモデルを推論。Qwen3.5-122B は MoE（Mixture of Experts）で、122B パラメータ中 ~10B だけが毎回アクティブになるため、Apple Silicon でも高速に動く。

## モデル

| スロット | モデル | パラメータ | RAM | 用途 |
|---------|-------|-----------|-----|------|
| main (:5000) | Qwen3.5-122B-A10B-4bit | 122B (MoE, active 10B) | ~60GB | 汎用・高品質 |
| fast (:5001) | Qwen3.5-35B-A3B-4bit | 35B (MoE, active 3B) | ~8GB | 高速・軽量タスク |

128GB Mac なら両方同時に載る。64GB の場合は main のみ起動される。

## カスタマイズ

### 別のモデルを使う

環境変数で上書き、または `~/ai.sh` と `anthropic_proxy.py` を編集:

```bash
# 環境変数で上書き
export MLX_MODEL_MAIN="mlx-community/Qwen3-235B-A22B-Instruct-2507-4bit"
export MLX_MODEL_FAST="mlx-community/Qwen3.5-9B-4bit"

# おすすめの組み合わせ
# 128GB: 122B + 35B（デフォルト）
# 64GB:  35B + 9B
# 32GB:  9B のみ
```

### モデルルーティングを変更

`anthropic_proxy.py` の `MODEL_ROUTES` を編集:

```python
MODEL_ROUTES = {
    "claude-sonnet-4-6": "main",   # → 122B
    "claude-haiku-4-5":  "fast",   # → 35B
    "claude-opus-4-6":   "main",   # → 122B
}
```

### ポート変更

`~/ai.sh` の `PORT_MAIN`, `PORT_FAST`, `PROXY_PORT` を編集。

## トラブルシューティング

| エラー | 対処 |
|-------|------|
| ECONNREFUSED | サーバー未起動。`~/ai.sh start` を実行 |
| MLX timeout | モデルロード中。`tail -f ~/mlx_server.log` で確認 |
| ツールが実行されない | `--dangerously-skip-permissions` フラグを確認 |
| メモリ不足 | 122Bモデルは ~60GB必要。小さいモデルに変更 |

## License

MIT
