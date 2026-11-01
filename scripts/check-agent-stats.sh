#!/bin/bash
# Compiles AgentStats.swift with a small check program and runs it. Pass a saved custom_stats
# record (JSON) to also check a live row from the hub.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
swiftc -O -o "$out/check" Sources/Models/AgentStats.swift scripts/agent-stats-check/main.swift
"$out/check" "$@"
