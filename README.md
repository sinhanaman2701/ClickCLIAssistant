# ClickCLIAssistant

Native macOS MVP for a selection-based AI assistant:

- select text
- get a small `Use Skills` popup above the selection
- click to open a dropdown of markdown-backed skills
- use `Use Skills` from the macOS Services / right-click menu
- run the selected skill through local Ollama using a cloud model such as `kimi-k2.5:cloud`
- preview and copy the result

## Current State

This repository currently includes:

- a native macOS app target
- a top-level CLI command
- a macOS Service registered as `Use Skills`
- local config storage
- dynamic markdown skill loading from a folder
- skill folder watching so new `.md` files appear automatically
- local Ollama API integration
- a preview window for transformed output

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
- save your default model choice
- launch the app automatically when setup succeeds
- register the app bundle so `Use Skills` appears in the Services menu

Important:

- when prompted, paste a model command like `ollama run kimi-k2.5:cloud`
- do not paste multiple shell commands into one prompt

## CLI Commands

```bash
swift run click-assistant help
swift run click-assistant install
swift run click-assistant run
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

## Run

The installer should launch the app automatically.

You can also run it manually:

```bash
swift run click-assistant run
```

After the app is running, select text in any supported macOS app and use:

- right-click menu
- Services
- `Use Skills`

## Skills

Skills are loaded from the configured skills folder. By default:

```text
~/.ai-assistant/skills
```

Any new `.md` file added there should automatically appear in the popup dropdown.

Example skill:

```md
# Grammar Correction

## Description
Correct grammar, spelling, punctuation, and basic sentence flow.

## Prompt
Correct the grammar, spelling, punctuation, and basic sentence flow of the selected text. Return only the corrected text. Do not explain the changes.
```

## Current Gaps

- popup positioning is best-effort and depends on macOS accessibility APIs
- app-to-app text selection support will vary
- preview is copy-first only; it does not replace text in the source app yet
- the app needs macOS Accessibility permission to inspect selected text
