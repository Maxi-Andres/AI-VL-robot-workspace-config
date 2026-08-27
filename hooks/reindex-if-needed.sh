#!/usr/bin/env bash
# reindex-if-needed.sh — keep the codebase-memory graph fresh across the whole workspace.
#
# Wired into .claude/settings.json on SessionStart and Stop. Discovers every git repo
# under the workspace (depth 3, which covers the umbrella + child layout) and computes a
# signature from the current commit plus the working-tree status; it re-indexes a repo
# ONLY when that signature changed since the last run. Signatures are cached under
# .claude/.reindex-state/. Indexing is itself incremental (~0.2 s/repo), so this is
# doubly cheap: a session with no code changes does nothing at all.
#
# Discovery is dynamic on purpose. The previous version of this hook lived in
# AI-VL-ecosystem with REPOS=(. AI-VL-core AI-VL-backend AI-VL-frontend) hardcoded, so
# it never covered unitree_ros2 or the robot repos, and it never ran at all from the
# workspace root — the graph sat 45 days stale with 4 of 11 repos indexed.
#
# It must never break a session: every step is guarded and the hook invokes it with
# `|| true`. Requires `codebase-memory-mcp` on PATH.
set -u

ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
STATE_DIR="$ROOT/.claude/.reindex-state"
mkdir -p "$STATE_DIR" 2>/dev/null || true

command -v codebase-memory-mcp >/dev/null 2>&1 || exit 0

# Every git repo in the workspace: the two umbrellas, their children, and the vendors.
while IFS= read -r gitdir; do
  repo="${gitdir%/.git}"
  [ -d "$repo" ] || continue

  head="$(git -C "$repo" rev-parse HEAD 2>/dev/null || echo no-git)"
  dirty="$(git -C "$repo" status --porcelain 2>/dev/null | sha1sum | cut -d' ' -f1)"
  sig="$head:$dirty"

  rel="${repo#"$ROOT"/}"
  key="$(echo "$rel" | tr '/.' '__')"
  state_file="$STATE_DIR/$key"
  [ "$sig" = "$(cat "$state_file" 2>/dev/null || echo)" ] && continue

  abs="$(cd "$repo" && pwd)"
  if codebase-memory-mcp cli index_repository "{\"repo_path\":\"$abs\"}" >/dev/null 2>&1; then
    echo "$sig" > "$state_file"
  fi
done < <(find "$ROOT" -maxdepth 3 -name .git -type d 2>/dev/null)

exit 0
