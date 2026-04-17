# ClickCLIAssistant

Browser-native MVP for a selection-based AI assistant:

- select text in the browser
- right-click and choose `Use Skills`
- pick a markdown-backed skill
- run the selected skill through local Ollama using a cloud model such as `kimi-k2.5:cloud`
- open a result page and copy the transformed output

## Current State

This repository currently includes:

- a top-level CLI command
- local config storage
- dynamic markdown skill loading from a folder
- local Ollama API integration
- a local browser bridge (`click-assistant bridge`)
- generated browser extension files for Chrome/Brave/Firefox

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
- launch the app automatically when setup succeeds

Important:

- when prompted, paste a model command like `ollama run kimi-k2.5:cloud`
- do not paste multiple shell commands into one prompt

## CLI Commands

```bash
swift run click-assistant help
swift run click-assistant install
swift run click-assistant run
swift run click-assistant bridge
swift run click-assistant doctor
swift run click-assistant uninstall
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

Then start the local bridge:

```bash
swift run click-assistant bridge
```

When text is selected, right-click and use `Use Skills`.

For Firefox:

1. Open `about:debugging#/runtime/this-firefox`.
2. Click `Load Temporary Add-on`.
3. Select `manifest.json` from:

```text
~/.ai-assistant/browser-extension/chromium
```

Then run `swift run click-assistant bridge` and use right-click `Use Skills`.

## Run

You can still run the macOS app manually:

```bash
swift run click-assistant run
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
- bridge startup is manual in this version (`click-assistant bridge`)
- result flow is copy-first only; it does not replace selected text in-page
