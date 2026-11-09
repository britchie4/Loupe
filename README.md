# Loupe

**Target elements, not screenshots.**

Loupe is a macOS accessibility inspector that generates AI-agent-ready output. I built this for myself to speed up Mac app development with Claude Code. Hopefully you find it useful too.

https://britchie4.github.io/Loupe/

## What it does

- Inspect any UI element in any Mac app
- Annotate what you want changed
- Copy structured, agent-readable output
- Paste into Claude Code, Cursor, or Codex and watch them build
- Or skip the pasting: with Agent Link, your coding agent reads your notes, asks questions, and reports back right in Loupe

## How it works

**Hover** — Point at any element in any app and see accessibility info in real-time.

**Annotate** — Click an element, describe the change you want in plain English.

**Copy** — Hit the copy button to get structured output with element roles, hierarchy paths, and search patterns.

**Build** — Paste into your AI assistant. It knows exactly which element to target — no screenshots, no guessing.

## Agent Link (new in 2.0)

Agent Link connects Loupe to your coding agent over MCP. Say "fix my Loupe notes" and your agent:

- reads every note with its element, location, and search patterns,
- asks you a question on a note when something is unclear (answer it right in Loupe),
- marks each note done with what it changed and where, so the badge turns green,
- can look at the app you picked to check its work, but can never click or type in it.

Agent Link is off until you turn it on in Loupe's **Settings**. Settings also has a setup button for Claude Code, Codex, Cursor, Xcode, or any other agent, with the exact steps for your copy of Loupe.

**Claude Code** (also covers the Code tab in the Claude desktop app):

```bash
claude mcp add --scope user loupe -- /Applications/Loupe.app/Contents/MacOS/Loupe --mcp
```

**Codex:**

```bash
codex mcp add loupe -- /Applications/Loupe.app/Contents/MacOS/Loupe --mcp
```

**Cursor:** choose Cursor in Loupe's Settings and click **Add to Cursor**, or add Loupe to `~/.cursor/mcp.json`:

```json
{
  "mcpServers": {
    "loupe": {
      "command": "/Applications/Loupe.app/Contents/MacOS/Loupe",
      "args": ["--mcp"]
    }
  }
}
```

**Claude desktop app (chat):** open **Settings > Developer > Edit Config** and add Loupe under `mcpServers`:

```json
{
  "mcpServers": {
    "loupe": {
      "command": "/Applications/Loupe.app/Contents/MacOS/Loupe",
      "args": ["--mcp"]
    }
  }
}
```

Then restart the Claude desktop app.

**Xcode's built-in agents:** Xcode runs its own Claude Agent and Codex with separate settings in `~/Library/Developer/Xcode/CodingAssistant`, so register Loupe there too:

```bash
CLAUDE_CONFIG_DIR="$HOME/Library/Developer/Xcode/CodingAssistant/ClaudeAgentConfig" claude mcp add --scope user loupe -- /Applications/Loupe.app/Contents/MacOS/Loupe --mcp
```

```bash
CODEX_HOME="$HOME/Library/Developer/Xcode/CodingAssistant/codex" codex mcp add loupe -- /Applications/Loupe.app/Contents/MacOS/Loupe --mcp
```

**Any other MCP agent:** choose **Other agent** in Loupe's Settings and paste the setup prompt into your agent's chat, or register `/Applications/Loupe.app/Contents/MacOS/Loupe --mcp` as a stdio server yourself.

### Teach your agent the workflow

The [loupe-notes skill](skills/loupe-notes/SKILL.md) walks an agent through the notes routine: pick up a note, ask when unclear, make the change, check it, report back. Install it for Claude Code, Codex, and other agents that read skills:

```bash
npx skills add britchie4/Loupe
```

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

## Updating

**Version 1.2.1 and later update themselves.** Loupe asks once whether to check for updates automatically. You can also choose **Check for Updates…** from the Loupe menu bar icon, or right-click the toolbar.

**On an older version?** Update by hand once:

1. Quit Loupe (right-click the toolbar and choose **Quit Loupe**).
2. [Download the latest release](https://github.com/britchie4/Loupe/releases/latest).
3. Drag Loupe to Applications, replacing the old copy. Your Accessibility permission carries over.

## Requirements

- macOS 14.0+ (Sonoma)
- Accessibility permissions — Loupe will prompt on first launch

## Inspired by

[agentation.dev](https://agentation.dev) — same concept for the web. Loupe does it for macOS.

## License

MIT — do what you want with it. See [LICENSE](LICENSE).
