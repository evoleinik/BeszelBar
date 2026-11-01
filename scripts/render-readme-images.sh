#!/bin/bash
# Draws docs/menu-bar.png and the two social-preview images with the app's own drawing code.
# Runs on a Mac. The social previews are uploaded by hand in each repo's Settings.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
swiftc -O -o "$out/render" Sources/Services/LiveMetrics.swift Sources/Menu/StatusImage.swift Sources/Menu/PixelFont.swift \
  scripts/readme-image/main.swift
mkdir -p docs
"$out/render" docs
ls -l docs/*.png
