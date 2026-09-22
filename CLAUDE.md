# CLAUDE.md — workspace root

Guidance for Claude Code opened at `~/Desktop`. Kept short on purpose; everything else is a
pointer.

This is a **multi-repo workspace: 11 git repos**, two umbrellas plus two vendors. Open
sessions **here**, not inside a sub-repo — the MCP config, the review skill and the reindex
hook are all scoped to this directory.

```
AI-VL-ecosystem/  {AI-VL-core, AI-VL-backend, AI-VL-frontend}   the app
robot-ecosystem/  {robot-video-pipeline, robot-telemetry-agent,
                   robot-command-relay, robot-splunk-docs}      the robot side
unitree_ros2/     own fork: robot_executor + robot_camera_bridge
unitree_sdk2/     pristine vendor — never patch, never review
```

## Hard rules

- **Never `git commit` or `git push`.** Make edits, verify, report. The user commits.
- **English in every repo** — code, comments, identifiers, strings, scripts, docs. The
  declared exceptions are all planning/diagnosis narrative, never code: `AI-VL-core/FIX.txt`,
  `robot-splunk-docs/*.md` and `.claude/ROADMAP.md`.
  Open discrepancy: five files under `AI-VL-ecosystem/docs/` are in Spanish while that repo's
  own CLAUDE.md declares English-only with `FIX.txt` as the single exception. Undecided —
  either translate them or declare the exception there.
- **`grep` here is not grep.** It is `ugrep --ignore-files`, so it respects `.gitignore` — and
  the umbrellas gitignore their child repos. A recursive `grep -r` from `~/Desktop` returns
  **zero hits inside the three AI-VL app repos**. For any verification sweep use
  `/usr/bin/grep -r`.

## Read these

| For | Read |
|---|---|
| The engineering standard — security, latency, tests, layout, with the incident behind each rule | `.claude/skills/cr/references/standard.md` |
| **What to do, in what order, and the real state of every capability** | **`.claude/ROADMAP.md`** — the single source of truth. Split on 2026-09-22: it now holds orientation only (§0 how to read · §1 the two robots · §2 verified state · §4 what blocks · §9 open decisions), and the rest lives in `.claude/roadmap/` — `GO2.md` (§5), `G1.md` (§6), `PLATAFORMA.md` (§7-§8), `BITACORA.md` (§3, §10, §11). **Section numbers did not change**, so an existing `§5.2` reference still resolves; the map is in `ROADMAP.md` §0 |
| Reviewing uncommitted work across all repos | the `/cr` skill |
| Where things are in the code | the `codebase-memory` graph (`get_architecture`, `search_graph`) — all 11 repos, reindexed after **every** edit by the `PostToolUse` hook, not just at session end |

Two things about that graph, both measured on 2026-09-22, both of which produced a wrong
conclusion before they were understood:

- **`detect_changes` does not tell you whether the index is stale.** It returns the same file
  list before and after a successful reindex, and it lists files last touched weeks ago. To
  check freshness, look a symbol up: `search_graph` for something just written must find it,
  at the right file and line.
- **The MCP server can answer from an older view than the store holds.** The hook updates the
  store through the CLI; the long-running server does not always pick that up. Seen directly:
  the CLI found a symbol the MCP query did not, at the same moment. If a graph answer looks
  stale, call `index_repository` **through the MCP** — that refreshes what your queries see.

Before changing anything in the transport layer, read
`AI-VL-ecosystem/docs/TRANSPORT_SDK_VS_ROS2.md`: what runs today is the ROS2 transport, which
is the reverse of the recorded decision.
