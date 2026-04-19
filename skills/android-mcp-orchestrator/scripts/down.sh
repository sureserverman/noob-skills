#!/bin/bash
# android-mcp-orchestrator down.sh — tear down the MCP stack
# Usage: ./down.sh [--mock] [compose-dir]
#   --mock       also tear down the mock profile (if the stack was started with --mock)
#   compose-dir  path to the android-emu-mcp compose root (default: ../mcp/android-emu-mcp)

set -eu

MOCK=0
COMPOSE_DIR=""
for arg in "$@"; do
  case "$arg" in
    --mock) MOCK=1 ;;
    *) COMPOSE_DIR="$arg" ;;
  esac
done
: "${COMPOSE_DIR:=../mcp/android-emu-mcp}"

cd "$COMPOSE_DIR"
if [ "$MOCK" -eq 1 ]; then
  podman compose --profile mock down
else
  podman compose down
fi
