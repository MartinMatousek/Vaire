#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/../TimeKeeperKit"
swift build -c release
BIN_PATH=$(swift build -c release --show-bin-path)/timekeeper-cli

mkdir -p ~/.local/bin
cp "$BIN_PATH" ~/.local/bin/timekeeper-cli
chmod +x ~/.local/bin/timekeeper-cli

echo "Installed timekeeper-cli to ~/.local/bin/timekeeper-cli"
~/.local/bin/timekeeper-cli 2>&1 || true
