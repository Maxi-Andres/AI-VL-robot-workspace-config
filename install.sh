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

# Two files Claude Code reads from the workspace ROOT, which is outside .claude/ — so they
# are versioned in here and linked into place.
link_into_root() {
  local src="$1" dst="$ROOT/$2"
  if [ -e "$dst" ] && [ ! -L "$dst" ]; then
    echo "[install] $dst exists and is a real file — leaving it alone." >&2
    echo "[install] Compare it with $HERE/$src and remove it if you want the linked one." >&2
  else
    ln -sfn "$HERE/$src" "$dst"
    echo "[install] linked $dst -> .claude/$src"
  fi
}
link_into_root mcp.json .mcp.json
link_into_root CLAUDE.md CLAUDE.md

chmod +x "$HERE/hooks/"*.sh 2>/dev/null || true
echo "[install] hooks are executable"

if command -v codebase-memory-mcp >/dev/null 2>&1; then
  "$HERE/hooks/reindex-if-needed.sh" && echo "[install] codebase-memory graph indexed"
else
  echo "[install] codebase-memory-mcp not on PATH — install it to get the code graph:" >&2
  echo "[install]   curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh | bash -s -- --ui --skip-config" >&2
fi

echo "[install] done. Open Claude Code from $ROOT and approve the MCP server once."
