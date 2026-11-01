#!/bin/bash
# Compiles the live-graph sources with a small check program and runs it.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
swiftc -O -o "$out/check" Sources/Services/LiveMetrics.swift Sources/Menu/StatusImage.swift Sources/Menu/PixelFont.swift scripts/live-check/main.swift
"$out/check"
