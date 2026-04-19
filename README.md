# ClickCLIAssistant

Selection-based AI assistant with two entry paths:

- global OS hotkey launcher (`Cmd+Shift+Space`) via `ai-assistant-app`
- browser right-click `Use Skills` via extension + local bridge
- markdown-backed skills from local `.md` files
- Dual Setup Architecture:
  - Local Ollama fallback (fast, offline inference using models like `qwen2.5:1.5b`)
  - Ollama Cloud API Key flow (instant sub-second TTFT for heavy cloud models like `kimi-k2.5:cloud` directly from official servers)

## Current State

This repository currently includes:

- a top-level CLI command
- local config storage
- dynamic markdown skill loading from a folder
- local Ollama API integration
- desktop launcher app with global hotkey and contextual result popover
- a local browser bridge (`click-assistant bridge`)
- generated browser extension files for Chrome/Brave/Firefox
- bridge auto-start via `launchd` after install

## Prerequisites

1. macOS
2. Swift toolchain / Xcode Command Line Tools

## Install

One-line bootstrap from anywhere:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/sinhanaman2701/ClickCLIAssistant/main/scripts/install.sh)
```

Manual install from the repository root:

```bash
swift run click-assistant install
```

The installer will:

- detect Ollama
- install Ollama automatically with Homebrew if it is missing and Homebrew is available
- ask for an Ollama model command such as `ollama run kimi-k2.5:cloud`
- extract and verify the model with a one-shot Ollama run
- create the local config file at `~/.ai-assistant/config.json`
- create the skills folder
- add a sample markdown skill
- generate a Chromium browser extension
- save your default model choice

Important:

- when prompted, paste a model command like `ollama run kimi-k2.5:cloud`
- **Large Documents**: For handling large documents (4,000+ words), we recommend using `gemini-3-flash-preview:cloud`. (Note: This is resource-heavy; users are free to use any other Ollama cloud model).
- do not paste multiple shell commands into one prompt

## CLI Commands

```bash
swift run click-assistant help
swift run click-assistant install
swift run click-assistant bridge
swift run click-assistant doctor
swift run click-assistant uninstall
swift run ai-assistant-app
```

If you used the bootstrap script, the repo is cloned to:

```text
~/.click-cli-assistant-src
```

## Remove Completely

To remove the product from your system:

```bash
cd ~/.click-cli-assistant-src
swift run click-assistant uninstall
```

That removes:
- `~/.ai-assistant`
- `~/.click-cli-assistant-src`

Non-interactive uninstall:

```bash
cd ~/.click-cli-assistant-src
swift run click-assistant uninstall --yes
```

## Browser Setup

After install, load the generated extension in Chrome or Brave:

1. Open `chrome://extensions` (or `brave://extensions`).
2. Enable Developer mode.
3. Click `Load unpacked`.
4. Select:

```text
~/.ai-assistant/browser-extension/chromium
```

Bridge auto-start is configured during install. If needed, you can still run it manually:

```bash
swift run click-assistant bridge
```

When text is selected, right-click and use `Use Skills`.

## OS Hotkey Launcher

Run:

```bash
swift run ai-assistant-app
```

Use:

1. Select text in any app.
2. Press `Cmd+Shift+Space`.
3. Choose a skill in the compact launcher.
4. Use `Copy` or `Replace` in the result popover.

Notes:
- `Accessibility` permission is required for reliable selection read/replace.
- Selection capture includes fast AX-first read with clipboard fallback for apps that do not expose AX selected text directly.

For Firefox:

1. Open `about:debugging#/runtime/this-firefox`.
2. Click `Load Temporary Add-on`.
3. Select `manifest.json` from:

```text
~/.ai-assistant/browser-extension/chromium
```

Bridge auto-start is configured during install. If needed, run `swift run click-assistant bridge` and use right-click `Use Skills`.

## Bridge Auto-Start

`click-assistant install` now installs a LaunchAgent:

```text
~/Library/LaunchAgents/com.clickcliassistant.bridge.plist
```

It points to:

```text
~/.ai-assistant/bin/click-assistant bridge
```

So the bridge starts automatically on login and keeps running in the background.

Check status:

```bash
swift run click-assistant doctor
```

## Skills

Skills are loaded from the configured skills folder. By default:

```text
~/.ai-assistant/skills
```

Any new `.md` file added there should automatically appear in the browser menu skill list.

Example skill:

```md
# Structured Prompt

## Description
Convert rough text into a clean, structured prompt.

## Prompt
Rewrite the selected text into a structured prompt with sections for goal, context, constraints, and desired output.
```

## Current Gaps

- Safari packaging is not added yet
- Firefox loading is temporary in this version (debug load flow)
- manual bridge startup is still available (`click-assistant bridge`) as a fallback
- some apps/sites still expose selection inconsistently, so fallback capture may vary by target app
