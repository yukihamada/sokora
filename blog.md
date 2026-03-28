# M5 Max 128GBでClaude Codeをローカル実行 — API費用ゼロで爆速AI開発環境を構築した話

## TL;DR

Apple M5 Max (128GB) に Qwen3.5-122B を載せて、Claude Code をローカルで完全動作させた。API費用ゼロ、ツール実行対応、画像生成・動画生成・画像理解まで全部ローカル。Ollamaのデフォルト設定から始めて、最終的に **2.5倍の高速化** を達成した。

**ソースコード**: [github.com/yukihamada/local-claude](https://github.com/yukihamada/local-claude)

---

## なぜこれをやったのか

Claude Code は最高のAIコーディングツールだが、毎月のAPI費用が馬鹿にならない。特にエージェントモードでバリバリ使うと、1日で数十ドル飛ぶこともある。

M5 Max (128GB) を手に入れたとき、ふと思った。「122Bパラメータのモデルがメモリに載るなら、ローカルで Claude Code を動かせるのでは？」

結果から言うと、**動いた**。しかもちゃんとツールを実行する。ファイルを読み書きし、コマンドを叩き、コードを生成する。本家と同じように。

---

## ステップ1: Ollama でまず動かす（ベースライン）

最初は Ollama で試した。一番簡単だから。

```bash
ollama run qwen3.5:122b
```

動くには動く。でも問題があった：

- **速度**: ~30 tok/s（体感もっさり）
- **Claude Code非対応**: Ollama は OpenAI 互換APIだが、Claude Code は Anthropic独自プロトコル (`/v1/messages`) を使う
- **tool_use非対応**: Claude Code の核心機能であるツール実行ができない

つまり Ollama だと「チャットはできるけど Claude Code としては使えない」状態。

---

## ステップ2: MLX に切り替える（+33% 高速化）

Apple の MLX フレームワークに切り替えた。MLX は Apple Silicon のユニファイドメモリとGPUに直接アクセスするため、Ollama (llama.cpp) より 20-30% 速い。

```bash
pip install mlx-lm
mlx_lm.server --model mlx-community/Qwen3.5-122B-A10B-4bit --port 5000
```

さらに MLX サーバーのフラグを最適化：

```bash
mlx_lm.server --model mlx-community/Qwen3.5-122B-A10B-4bit \
  --prefill-step-size 4096 \    # プロンプト処理の高速化
  --prompt-cache-size 8 \       # KVキャッシュ保持
  --port 5000
```

**結果: 45 → 60 tok/s (+33%)**

prompt cache が効いて、同じパターンのプロンプトは2回目以降が爆速になる。Claude Code は似たようなシステムプロンプトを毎回送るので、これが効く。

---

## ステップ3: Anthropic互換プロキシを作る

ここが一番大変だった。Claude Code は Anthropic の `/v1/messages` API を使う。MLX サーバーは OpenAI の `/v1/chat/completions` を喋る。この2つを橋渡しするプロキシが必要。

最初は LiteLLM を試したが、Claude Code が送る `claude-sonnet-4-6` というモデル名を認識できなかった。結局、自前でプロキシを書いた。

**変換が必要なもの:**

| Anthropic 形式 | OpenAI 形式 |
|---------------|-------------|
| `tools[].input_schema` | `tools[].function.parameters` |
| `content[].type: "tool_use"` | `message.tool_calls[]` |
| `content[].type: "tool_result"` | `role: "tool"` メッセージ |
| `stop_reason: "tool_use"` | `finish_reason: "tool_calls"` |
| `content[].type: "image"` (base64) | `content[].type: "image_url"` |

特に **tool_use の変換** が重要。これがないと Claude Code はコマンドを「提案」するだけで実行しない。本家 Claude との最大の違いがここ。

---

## ステップ4: Rust で書き直す（-55% レイテンシ）

Python (aiohttp) で書いたプロキシはちゃんと動いたが、リクエストごとに ~110ms のオーバーヘッドがあった。これは体感で分かるレベル。

Rust (axum) で書き直した結果：

| | Python (aiohttp) | Rust (axum) |
|---|---|---|
| レイテンシ | 584ms | **262ms** |
| メモリ使用量 | ~300MB | **~5MB** |

**55% のレイテンシ削減、メモリ 1/60。** Rust の威力。

コネクションプーリング、ゼロコピーストリーミング、TCP keepalive 最適化も入れた。

---

## ステップ5: マルチモデル自動ルーティング

128GB あるので、複数モデルを同時に載せた：

| ポート | モデル | 用途 | RAM |
|-------|-------|------|-----|
| :5000 | Qwen3.5-122B-A10B | 汎用（Sonnet/Opus相当） | ~60GB |
| :5001 | Qwen3.5-35B-A3B | 高速（Haiku相当） | ~8GB |
| :5002 | Qwen3-VL-8B | 画像理解 | ~5GB |

プロキシが Claude Code のモデル名で自動振り分け：
- `claude-sonnet-4-6` → 122B
- `claude-haiku-4-5` → 35B（2倍速）
- 画像が含まれるメッセージ → VL-8B（自動検出）

合計 ~73GB。128GB Mac なら余裕。

---

## ステップ6: 画像・動画生成もローカルで

せっかくのGPUなので、生成AI も載せた：

- **画像**: FLUX.1-schnell (mflux) — 1024x1024 が **約17秒**
- **動画**: Wan 2.1 — 480x832, 17フレームが **約10分**

画像/動画生成はオンデマンドで実行し、終わったらメモリ解放。常駐LLMに影響しない。

---

## 最終的なパフォーマンス比較

| 指標 | Ollama (初期) | 最適化後 | 改善率 |
|------|-------------|---------|--------|
| 推論速度 (122B) | ~30 tok/s | **60 tok/s** | **+100%** |
| 推論速度 (35B) | - | **116 tok/s** | - |
| プロキシ レイテンシ | - | **262ms** | - |
| プロキシ メモリ | ~300MB (Python) | **5MB (Rust)** | **-98%** |
| tool_use | 非対応 | **完全対応** | - |
| 画像理解 | 非対応 | **自動ルーティング** | - |
| 月額API費用 | $0 (でも使えない) | **$0 (全機能動作)** | - |

---

## アーキテクチャ図

```
                                          ┌─ MLX :5000 → Qwen3.5-122B (Sonnet/Opus)
Claude Code  →  Rust Proxy (:4001)  ──────┼─ MLX :5001 → Qwen3.5-35B  (Haiku/高速)
  (tool_use)     (Anthropic↔OpenAI変換)    └─ VLM :5002 → Qwen3-VL-8B  (画像→自動)

                  ┌─ FLUX.1 (画像生成, ~17s/枚)
  ~/ai.sh img  ───┘
  ~/ai.sh vid  ───── Wan 2.1 (動画生成, ~10min)
```

---

## セットアップ（1コマンド）

新しい Mac で一発セットアップ：

```bash
bash setup.sh
```

起動：
```bash
~/ai.sh start
```

```
  ╦  ╔═╗╔═╗╔═╗╦    ╔═╗╦
  ║  ║ ║║  ╠═╣║    ╠═╣║
  ╩═╝╚═╝╚═╝╩ ╩╩═╝  ╩ ╩╩
  ─────────────────────────
  Apple Silicon AI Runtime

  ● LLM 122B (Sonnet/Opus)  :5000
  ● LLM 35B  (Haiku)        :5001
  ● Vision (auto-route)     :5002
  ● Proxy (Rust)            :4001

  Ready http://192.168.0.47:4001
```

あとは `cld` で Claude Code 起動。`clc` で本家に切り替え。

---

## 使ったもの

- **ハードウェア**: Mac M5 Max 128GB
- **LLMフレームワーク**: MLX (Apple)
- **モデル**: Qwen3.5-122B-A10B-4bit, Qwen3.5-35B-A3B, Qwen3-VL-8B
- **プロキシ**: Rust (axum) — Anthropic↔OpenAI変換
- **画像生成**: FLUX.1-schnell (mflux)
- **動画生成**: Wan 2.1 (diffusers)
- **メニューバー**: rumps (Python)

---

## これからどうなるか

1. **モデルの進化**: Qwen4, Llama4 など新モデルが出るたびにMLXコミュニティが量子化版を出す。swap するだけ
2. **Apple の最適化**: macOS 26.2+ の Neural Accelerators で MLX がさらに速くなる。M5 は M4 の 3.8倍速
3. **プライバシー**: コードが一切外部に送信されない。機密プロジェクトでも安心
4. **コスト**: 初期投資 (Mac) のみ。月額ゼロ。ヘビーユーザーなら 2-3ヶ月で元が取れる

ローカルAIの時代が来ている。M5 のユニファイドメモリ 128GB で 122B モデルが余裕で動く。あと2年もすれば、256GB の Mac に 400B モデルが載る時代が来るだろう。

---

**ソースコード**: [github.com/yukihamada/local-claude](https://github.com/yukihamada/local-claude)

ワンコマンドで試せる。`bash setup.sh` でどうぞ。
