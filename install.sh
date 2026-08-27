#!/usr/bin/env bash
# install.sh — put this workspace config in place on a new machine.
#
# This repo IS the .claude directory of the workspace, so it is cloned into position:
#     git clone <this-repo> ~/Desktop/.claude
#     bash ~/Desktop/.claude/install.sh
#
# The only thing that cannot live inside .claude/ is .mcp.json, which Claude Code reads from
# the workspace root — so it is versioned here as mcp.json and linked into place.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$HERE")"

if [ -e "$ROOT/.mcp.json" ] && [ ! -L "$ROOT/.mcp.json" ]; then
  echo "[install] $ROOT/.mcp.json exists and is a real file — leaving it alone." >&2
  echo "[install] Compare it with $HERE/mcp.json and remove it if you want the linked one." >&2
else
  ln -sfn "$HERE/mcp.json" "$ROOT/.mcp.json"
  echo "[install] linked $ROOT/.mcp.json -> .claude/mcp.json"
fi

chmod +x "$HERE/hooks/"*.sh 2>/dev/null || true
echo "[install] hooks are executable"

if command -v codebase-memory-mcp >/dev/null 2>&1; then
  "$HERE/hooks/reindex-if-needed.sh" && echo "[install] codebase-memory graph indexed"
else
  echo "[install] codebase-memory-mcp not on PATH — install it to get the code graph:" >&2
  echo "[install]   curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh | bash -s -- --ui --skip-config" >&2
fi

echo "[install] done. Open Claude Code from $ROOT and approve the MCP server once."
