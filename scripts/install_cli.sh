#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/../VaireKit"
swift build -c release
BIN_PATH=$(swift build -c release --show-bin-path)/vaire

mkdir -p ~/.local/bin
cp "$BIN_PATH" ~/.local/bin/vaire
chmod +x ~/.local/bin/vaire

echo "Installed vaire to ~/.local/bin/vaire"
~/.local/bin/vaire 2>&1 || true
