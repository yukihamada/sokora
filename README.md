# Sokora 🧠

Apple Silicon Mac で Claude Code と Aider をローカル実行。API費用ゼロ、完全オフライン動作。

> **16GB M2 Air から 128GB M5 Max まで全対応。** RAMを自動検出して最適なモデルを選択。

## セットアップ

```bash
bash setup.sh
```

## 使い方

```bash
~/ai.sh start   # MLX + プロキシ起動
cld             # Claude Code (ローカル)
aid             # Aider (ローカル 122B)
```

## 仕組み

```
                                        ┌─ MLX :5000 → Qwen3.5-122B
Claude Code → Sokora Proxy (:4001) ────┼─ MLX :5001 → Qwen3.5-35B
Aider       → /v1/chat/completions     └─ VLM :5002 → Qwen3-VL-8B
```

## 機能

- **Anthropic + OpenAI 互換プロキシ** — Claude Code / Aider どちらも動く
- **Webダッシュボード** — http://localhost:4001 でモデル状態・接続情報を確認
- **メニューバーアプリ** — Start/Stop/画像生成/DePIN/Tunnel を1クリック
- **DePINノード** — Solanaで推論を外部提供してSOL獲得
- **Cloudflare Tunnel** — どこからでもアクセス可能

## モデル (RAM別自動選択)

| RAM | Main | Fast | Vision |
|-----|------|------|--------|
| 16GB | Qwen3.5-4B | — | — |
| 32GB | Qwen3.5-35B | — | VL-4B |
| 64GB | Qwen3.5-35B | 9B | VL-8B |
| 128GB | Qwen3.5-122B | 35B | VL-8B |

## License

MIT
