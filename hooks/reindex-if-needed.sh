#!/usr/bin/env bash
# reindex-if-needed.sh — keep the codebase-memory graph fresh across the whole workspace.
#
# Wired into .claude/settings.json on SessionStart, PostToolUse (Edit|Write|NotebookEdit)
# and Stop. PostToolUse is the one that matters in practice: with only Stop, the graph is
# correct but always one turn behind, so a lookup made in the same turn as an edit reads the
# code as it was BEFORE the edit. Discovers every git repo
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
# CONCURRENCY. PostToolUse fires on every edit, so several copies can overlap on a burst of
# them. A non-blocking flock means the extra copies EXIT rather than queue: whoever holds the
# lock is already indexing, and the signature check makes the next run pick up anything it
# missed. Queueing would turn a 10-edit burst into 10 serialized index passes.
#
# NOTE FOR WHOEVER CHECKS FRESHNESS: `detect_changes` is NOT the way to do it. It reports the
# same file list before and after a successful reindex, and it lists files last modified
# weeks ago — it answers some other question, and reading it as "what the index is missing"
# produced a confident, wrong conclusion on 2026-09-22. What actually proves the index is
# current is looking a symbol up: `search_graph` for something just written must find it,
# with the right file and line numbers.
#
# It must never break a session: every step is guarded and the hook invokes it with
# `|| true`. Requires `codebase-memory-mcp` on PATH.
set -u

ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
STATE_DIR="$ROOT/.claude/.reindex-state"
mkdir -p "$STATE_DIR" 2>/dev/null || true

command -v codebase-memory-mcp >/dev/null 2>&1 || exit 0

# Re-exec under a non-blocking lock, once. `-n` = give up instead of waiting; the guard
# variable is what stops the re-exec from recursing.
if [ "${REINDEX_LOCKED:-}" != 1 ]; then
  export REINDEX_LOCKED=1
  exec flock -n "$STATE_DIR/.lock" "$0" "$@" || exit 0
fi

# Every git repo in the workspace: the two umbrellas, their children, and the vendors.
while IFS= read -r gitdir; do
  repo="${gitdir%/.git}"
  [ -d "$repo" ] || continue

  # The signature must follow CONTENT, not the file list. It used to be
  # sha1(git status --porcelain), and that string is identical for "app.py is modified" and
  # "app.py is modified AGAIN" — so the hook saw the FIRST edit to a file and was blind to
  # every one after it. Measured 2026-09-22: two appends to the same file produced the exact
  # same signature, and the second never got indexed. With PostToolUse firing per edit that
  # is the common case, not an edge one.
  #
  # `git diff HEAD` carries the actual content of every tracked change; untracked files are
  # hashed individually because no diff covers them.
  head="$(git -C "$repo" rev-parse HEAD 2>/dev/null || echo no-git)"
  dirty="$( {
      git -C "$repo" diff HEAD 2>/dev/null
      git -C "$repo" ls-files --others --exclude-standard -z 2>/dev/null \
        | xargs -0 -r sha1sum 2>/dev/null
    } | sha1sum | cut -d' ' -f1 )"
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
