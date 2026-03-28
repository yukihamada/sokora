# Local Claude Code with MLX

Apple Silicon Mac で Claude Code をローカル実行。API費用ゼロ、ツール実行対応、完全オフライン動作。

> Qwen3.5-122B を MLX で動かし、Anthropic API互換プロキシ経由で Claude Code がそのまま使える

## 仕組み

```
Claude Code  →  Anthropic Proxy (:4001)  →  MLX Server (:5000)  →  Qwen3.5-122B
  (tool_use)     (Anthropic↔OpenAI変換)       (Apple GPU)            (4bit, ~60GB RAM)
```

Claude Code は本家 Anthropic API と同じプロトコルで通信するので、コマンド実行・ファイル読み書き・コード生成がそのまま動く。

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

**Qwen3.5-122B-A10B-4bit**（mlx-community）
- 122B パラメータ（MoE、アクティブ ~10B）
- 4bit量子化、ディスク ~40GB、RAM ~60GB
- 100以上の言語に対応、コード生成に強い
- ツール呼び出し（function calling）ネイティブ対応

## カスタマイズ

### 別のモデルを使う

`setup.sh` と `anthropic_proxy.py` の `MODEL` を変更:

```bash
# 小さめ（32GB+ RAM）
MODEL="mlx-community/Qwen3-32B-4bit"

# さらに小さめ（16GB+ RAM）
MODEL="mlx-community/Qwen3-8B-4bit"
```

### ポート変更

`~/ai.sh` の `MLX_PORT` と `PROXY_PORT` を編集。

## トラブルシューティング

| エラー | 対処 |
|-------|------|
| ECONNREFUSED | サーバー未起動。`~/ai.sh start` を実行 |
| MLX timeout | モデルロード中。`tail -f ~/mlx_server.log` で確認 |
| ツールが実行されない | `--dangerously-skip-permissions` フラグを確認 |
| メモリ不足 | 122Bモデルは ~60GB必要。小さいモデルに変更 |

## License

MIT
