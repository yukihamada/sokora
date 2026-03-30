<div align="center">

![Sokora Banner](https://img.shields.io/badge/Sokora-Local%20AI%20for%20Apple%20Silicon-blue?style=for-the-badge&logo=apple)

[![macOS](https://img.shields.io/badge/macOS-14%2B-black?style=flat-square&logo=apple)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6-orange?style=flat-square&logo=swift)](https://swift.org/)
[![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)](LICENSE)
[![Stars](https://img.shields.io/github/stars/yukihamada/sokora?style=flat-square&logo=github)](https://github.com/yukihamada/sokora/stargazers)
[![MLX](https://img.shields.io/badge/MLX-Powered-purple?style=flat-square)](https://github.com/ml-explore/mlx)
[![DePIN](https://img.shields.io/badge/DePIN-Enabled-red?style=flat-square)](https://github.com/yukihamada/sokora)

# 🤖 Sokora

### **Run powerful AI models locally on Apple Silicon — and share them with the world**

*A native macOS menu bar app that turns your Mac into a local AI inference server.*
*Compatible with Claude Code, Aider, Open WebUI, and any OpenAI/Anthropic-compatible client.*

[English](#english) · [日本語](#日本語) · [中文](#中文) · [한국어](#한국어)

---

</div>

<a name="english"></a>

## ✨ Features

- **🖥️ Native Menu Bar App** — Runs quietly in your menu bar as a native Swift `.app` bundle. No Python, no terminal, no friction.
- **⚡ Apple Silicon Optimized** — Powered by [MLX](https://github.com/ml-explore/mlx), squeezing maximum performance from M1/M2/M3/M4 chips and unified memory.
- **🔌 Dual API Compatibility** — Speaks both **Anthropic** (`/v1/messages`) and **OpenAI** (`/v1/chat/completions`) protocols out of the box.
- **🌊 SSE Streaming** — Full server-sent events streaming for real-time token generation.
- **🛠️ Tool Use** — Supports `tool_use` / function calling for agentic workflows.
- **🌐 DePIN Mode** — Share your idle GPU over Cloudflare Tunnel and earn rewards while you're away.
- **😴 Sleep Prevention** — Keeps your Mac awake while serving requests.
- **🔒 Privacy First** — All inference runs 100% on-device. Your data never leaves your machine.

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Sokora.app (Swift)                       │
│  ┌─────────────┐   ┌───────────────┐   ┌─────────────────────┐ │
│  │  Menu Bar   │   │  Proxy Server │   │   DePIN Manager     │ │
│  │  UI / Prefs │──▶│  :4001 (HTTP) │   │  Cloudflare Tunnel  │ │
│  └─────────────┘   └───────┬───────┘   └─────────────────────┘ │
│                            │                                     │
│              ┌─────────────┼─────────────┐                      │
│              ▼             ▼             ▼                       │
│   /v1/messages    /v1/chat/completions  /health                  │
│   (Anthropic)     (OpenAI)              (Status)                 │
│              └─────────────┬─────────────┘                      │
│                            ▼                                     │
│                  ┌──────────────────┐                            │
│                  │   MLX Backend    │                            │
│                  │  (Python + mlx-lm)│                           │
│                  └──────────────────┘                            │
└─────────────────────────────────────────────────────────────────┘
         │                                        │
         ▼                                        ▼
  ┌─────────────┐                       ┌──────────────────┐
  │ Local Tools │                       │  Internet Users  │
  │ Claude Code │                       │  (DePIN / Share) │
  │ Aider       │                       └──────────────────┘
  │ Open WebUI  │
  └─────────────┘
```

---

## 🤖 Supported Models

| Model | Size | VRAM (Approx.) | Best For |
|-------|------|----------------|----------|
| **Qwen3.5-122B** | 122B | 64 GB+ | Maximum quality, complex reasoning |
| **Qwen3.5-35B** | 35B | 24 GB+ | Balanced quality & speed |
| **Qwen3-VL-8B** | 8B | 16 GB+ | Vision + language tasks |
| **DeepSeek-V4** | — | 32 GB+ | Code generation, analysis |

---

## 💾 Recommended Configuration by RAM

| Unified Memory | Recommended Model | Expected Speed |
|----------------|-------------------|----------------|
| 16 GB | Qwen3-VL-8B | ~30 tok/s |
| 24 GB | Qwen3.5-35B | ~20 tok/s |
| 48 GB | Qwen3.5-35B (full) | ~35 tok/s |
| 64 GB+ | Qwen3.5-122B | ~10 tok/s |
| 128 GB+ | Qwen3.5-122B (full) | ~20 tok/s |

---

## 🚀 Quick Start

### Step 1 — Clone the repository

```bash
git clone https://github.com/yukihamada/sokora ~/sokora
```

### Step 2 — Set up the MLX backend

```bash
brew install python@3.11
python3.11 -m venv ~/mlx_env
source ~/mlx_env/bin/activate
pip install mlx-lm
```

### Step 3 — Build the app

```bash
cd ~/sokora/LocalAI.app-src
swift build -c release
bash build-app.sh
```

### Step 4 — Install & launch

```bash
# Copy to Applications
cp -R Sokora.app /Applications/

# Launch now
open /Applications/Sokora.app

# — or — auto-start on login
cp com.sokora.menubar.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.sokora.menubar.plist
```

Sokora will appear as a robot icon (🤖) in your menu bar. Click it to select a model and start the server.

---

## 🔧 Usage

### Claude Code

```bash
export ANTHROPIC_BASE_URL=http://localhost:4001
claude
```

### Aider

```bash
export OPENAI_API_BASE=http://localhost:4001/v1
export OPENAI_API_KEY=local
aider --model openai/qwen3.5-35b
```

### Open WebUI

```
Settings → Connections → OpenAI API
URL: http://localhost:4001/v1
API Key: local
```

### curl (Anthropic format)

```bash
curl http://localhost:4001/v1/messages \
  -H "Content-Type: application/json" \
  -H "x-api-key: local" \
  -d '{
    "model": "qwen3.5-35b",
    "max_tokens": 1024,
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

### curl (OpenAI format)

```bash
curl http://localhost:4001/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3.5-35b",
    "stream": true,
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

---

## 🌐 DePIN — Share Your AI, Earn Rewards

**DePIN** (Decentralized Physical Infrastructure Network) mode lets you contribute your Mac's idle compute to a global AI network.

### How It Works

```
Your Mac (Sokora)
      │
      │ Cloudflare Tunnel (encrypted)
      ▼
Cloudflare Edge ──── Internet Users
      │                    │
      │                    ▼
      │           Sokora Network
      │         (request routing)
      └──────── Reward tracking
```

### Enabling DePIN

1. Open Sokora from the menu bar
2. Navigate to **DePIN Settings**
3. Toggle **"Share when idle"**
4. Paste your Cloudflare Tunnel token (get one free at [dash.cloudflare.com](https://dash.cloudflare.com))

### Privacy & Safety

- **Your data is never stored** — requests are forwarded in real-time only
- **Rate limiting** is enforced automatically
- **You control availability** — pause or stop sharing any time from the menu bar
- **Sleep prevention** — your Mac stays awake only while actively serving requests

---

## 🛠️ Build from Source

### Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| Xcode | 16+ | App Store |
| Swift | 6.0+ | Included with Xcode |
| Python | 3.11+ | `brew install python@3.11` |
| mlx-lm | latest | `pip install mlx-lm` |

### Build Steps

```bash
git clone https://github.com/yukihamada/sokora
cd sokora/LocalAI.app-src

# Build Swift binary
swift build -c release

# Bundle as .app
bash build-app.sh

# Output: Sokora.app
```

### Directory Structure

```
sokora/
├── LocalAI.app-src/        # Swift source code
│   ├── Sources/
│   │   ├── App/            # SwiftUI menu bar app
│   │   ├── Proxy/          # HTTP proxy server
│   │   └── DePIN/          # Cloudflare tunnel manager
│   ├── build-app.sh        # App bundle script
│   └── Package.swift
├── com.sokora.menubar.plist # LaunchAgent config
└── README.md
```

---

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Commit your changes: `git commit -m 'Add amazing feature'`
4. Push to the branch: `git push origin feature/amazing-feature`
5. Open a Pull Request

### Areas We'd Love Help With

- [ ] Additional model support
- [ ] Windows/Linux port (via alternative ML backends)
- [ ] Web dashboard for DePIN stats
- [ ] Model download manager UI
- [ ] Automated benchmarking

---

## 📄 License

MIT License — see [LICENSE](LICENSE) for details.

---

<a name="日本語"></a>

## 🇯🇵 日本語

### Sokoraとは

**Sokora**は、Apple Silicon搭載MacでローカルAI推論を実行するネイティブのメニューバーアプリです。Swiftで開発されており、Pythonや複雑なセットアップは不要。メニューバーに静かに常駐し、Claude Code、Aider、Open WebUIなど、あらゆるAIクライアントからローカルモデルを利用できます。

### 主な特徴

- **ネイティブアプリ** — `.app`バンドルとして動作。ターミナル常駐不要
- **Apple Silicon最適化** — MLXエンジンによりM1〜M4チップの性能を最大限に引き出す
- **二重API対応** — AnthropicとOpenAIの両プロトコルに対応
- **DePIN機能** — アイドル時にCloudflare Tunnel経由でAIを安全に共有・収益化
- **完全プライベート** — すべての推論はデバイス上で完結。データは外部に送信されない

### クイックスタート

```bash
# 1. クローン
git clone https://github.com/yukihamada/sokora ~/sokora

# 2. MLX環境セットアップ
brew install python@3.11
python3.11 -m venv ~/mlx_env
source ~/mlx_env/bin/activate
pip install mlx-lm

# 3. ビルド
cd ~/sokora/LocalAI.app-src
swift build -c release
bash build-app.sh

# 4. インストール＆起動
cp -R Sokora.app /Applications/
open /Applications/Sokora.app
```

### Claude Codeから使う

```bash
export ANTHROPIC_BASE_URL=http://localhost:4001
claude
```

メニューバーの🤖アイコンをクリックしてモデルを選択し、サーバーを起動してください。

---

<a name="中文"></a>

## 🇨🇳 中文（简体）

### 什么是 Sokora

**Sokora** 是一款专为 Apple Silicon Mac 设计的原生菜单栏应用，让您可以在本地运行强大的 AI 推理模型。基于 Swift 开发，无需 Python 或繁琐配置，只需将 `.app` 拖入应用程序文件夹即可使用。

支持与 Claude Code、Aider、Open WebUI 等所有兼容 OpenAI/Anthropic 协议的工具无缝对接。

### 核心功能

- **原生菜单栏应用** — 以 `.app` 形式静默运行于菜单栏，无需终端常驻
- **Apple Silicon 优化** — 基于 MLX 引擎，充分发挥 M1/M2/M3/M4 芯片的统一内存优势
- **双协议兼容** — 同时支持 Anthropic（`/v1/messages`）和 OpenAI（`/v1/chat/completions`）协议
- **DePIN 模式** — 通过 Cloudflare Tunnel 在闲置时安全共享您的算力，获取奖励
- **完全隐私** — 所有推理在本地完成，数据不离开您的设备

### 快速开始

```bash
# 1. 克隆仓库
git clone https://github.com/yukihamada/sokora ~/sokora

# 2. 配置 MLX 环境
brew install python@3.11
python3.11 -m venv ~/mlx_env
source ~/mlx_env/bin/activate
pip install mlx-lm

# 3. 编译
cd ~/sokora/LocalAI.app-src
swift build -c release
bash build-app.sh

# 4. 安装并启动
cp -R Sokora.app /Applications/
open /Applications/Sokora.app
```

### 与 Claude Code 配合使用

```bash
export ANTHROPIC_BASE_URL=http://localhost:4001
claude
```

点击菜单栏中的 🤖 图标，选择模型并启动服务器。

### 支持的模型

| 模型 | 显存需求 | 适用场景 |
|------|---------|---------|
| Qwen3.5-122B | 64 GB+ | 最高质量推理 |
| Qwen3.5-35B | 24 GB+ | 均衡性能 |
| Qwen3-VL-8B | 16 GB+ | 视觉 + 语言任务 |
| DeepSeek-V4 | 32 GB+ | 代码生成与分析 |

### DePIN — 共享算力，获取收益

启用 DePIN 模式后，Sokora 会在您的 Mac 闲置时通过 Cloudflare Tunnel 将算力安全地共享给全球用户。您始终掌控开关，随时可从菜单栏暂停或停止共享。所有连接均经过加密，您的隐私数据不受任何影响。

---

<a name="한국어"></a>

## 🇰🇷 한국어

### Sokora란?

**Sokora**는 Apple Silicon Mac에서 강력한 AI 추론 모델을 로컬로 실행하는 네이티브 메뉴바 앱입니다. Swift로 개발된 `.app` 번들로, Python이나 복잡한 설정 없이 바로 사용할 수 있습니다.

Claude Code, Aider, Open WebUI 등 OpenAI/Anthropic 호환 클라이언트와 즉시 연동됩니다.

### 주요 기능

- **네이티브 메뉴바 앱** — `.app` 번들로 조용히 메뉴바에서 실행. 터미널 상주 불필요
- **Apple Silicon 최적화** — MLX 엔진으로 M1/M2/M3/M4 칩의 통합 메모리를 최대한 활용
- **이중 API 호환** — Anthropic(`/v1/messages`)과 OpenAI(`/v1/chat/completions`) 프로토콜 동시 지원
- **DePIN 모드** — 유휴 시 Cloudflare Tunnel을 통해 AI를 안전하게 공유하고 보상 획득
- **완전한 프라이버시** — 모든 추론이 기기에서 완결. 데이터는 외부로 전송되지 않음

### 빠른 시작

```bash
# 1. 저장소 클론
git clone https://github.com/yukihamada/sokora ~/sokora

# 2. MLX 환경 설정
brew install python@3.11
python3.11 -m venv ~/mlx_env
source ~/mlx_env/bin/activate
pip install mlx-lm

# 3. 빌드
cd ~/sokora/LocalAI.app-src
swift build -c release
bash build-app.sh

# 4. 설치 및 실행
cp -R Sokora.app /Applications/
open /Applications/Sokora.app
```

### Claude Code와 함께 사용하기

```bash
export ANTHROPIC_BASE_URL=http://localhost:4001
claude
```

메뉴바의 🤖 아이콘을 클릭하여 모델을 선택하고 서버를 시작하세요.

### 지원 모델

| 모델 | 메모리 요구사항 | 활용 사례 |
|------|--------------|---------|
| Qwen3.5-122B | 64 GB+ | 최고 품질 추론 |
| Qwen3.5-35B | 24 GB+ | 균형 잡힌 성능 |
| Qwen3-VL-8B | 16 GB+ | 비전 + 언어 작업 |
| DeepSeek-V4 | 32 GB+ | 코드 생성 및 분석 |

### DePIN — 컴퓨팅 공유로 보상 획득

DePIN 모드를 활성화하면 Mac이 유휴 상태일 때 Cloudflare Tunnel을 통해 전 세계 사용자에게 AI 컴퓨팅을 안전하게 공유할 수 있습니다. 언제든지 메뉴바에서 공유를 일시 중지하거나 중단할 수 있으며, 모든 연결은 암호화되어 개인 정보가 보호됩니다.

---

<div align="center">

**Built with ❤️ for the Apple Silicon community**

[GitHub](https://github.com/yukihamada/sokora) · [Issues](https://github.com/yukihamada/sokora/issues) · [Discussions](https://github.com/yukihamada/sokora/discussions)

</div>
