# Loupe

**Target elements, not screenshots.**

Loupe is a macOS accessibility inspector that generates AI-agent-ready output. I built this for myself to speed up Mac app development with Claude Code. Hopefully you find it useful too.

https://britchie4.github.io/Loupe/

## What it does

- Inspect any UI element in any Mac app
- Annotate what you want changed
- Copy structured, agent-readable output
- Paste into Claude Code, Cursor, Codex — and watch them build

## How it works

**Hover** — Point at any element in any app and see accessibility info in real-time.

**Annotate** — Click an element, describe the change you want in plain English.

**Copy** — Hit the copy button to get structured output with element roles, hierarchy paths, and search patterns.

**Build** — Paste into your AI assistant. It knows exactly which element to target — no screenshots, no guessing.

## Install

**Download the latest release:**

[Download Loupe](https://github.com/britchie4/Loupe/releases/latest) (.dmg)

**Or build from source:**

```bash
git clone https://github.com/britchie4/Loupe.git
cd Loupe
open Loupe.xcworkspace
```

Build and run with Xcode (Cmd+R).

## Requirements

- macOS 14.0+ (Sonoma)
- Accessibility permissions — Loupe will prompt on first launch

## Inspired by

[agentation.dev](https://agentation.dev) — same concept for the web. Loupe does it for macOS.

## License

MIT — do what you want with it. See [LICENSE](LICENSE).
