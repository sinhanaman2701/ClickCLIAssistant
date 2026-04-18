#!/usr/bin/env bash

set -euo pipefail

REPO_URL="https://github.com/sinhanaman2701/ClickCLIAssistant.git"
INSTALL_DIR="${HOME}/.click-cli-assistant-src"

echo "ClickCLIAssistant bootstrap"
echo

# Kill any stale running instance of the GUI
pkill -f "ai-assistant-app" || true

if ! command -v git >/dev/null 2>&1; then
  echo "git is required but not installed."
  exit 1
fi

if ! command -v swift >/dev/null 2>&1; then
  echo "Swift is required but not installed."
  echo "Install Xcode Command Line Tools first:"
  echo "  xcode-select --install"
  exit 1
fi

if [ -d "${INSTALL_DIR}/.git" ]; then
  echo "Updating existing repository at ${INSTALL_DIR}"
  git -C "${INSTALL_DIR}" pull --ff-only
else
  echo "Cloning repository to ${INSTALL_DIR}"
  git clone "${REPO_URL}" "${INSTALL_DIR}"
fi

cd "${INSTALL_DIR}"
swift run click-assistant install

echo
echo "Starting the Desktop Assistant in the background..."
nohup swift run ai-assistant-app > /dev/null 2>&1 &

echo "Installation complete! Try pressing Cmd+Shift+Space"
