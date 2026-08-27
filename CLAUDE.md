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
- **English in every repo** — code, comments, identifiers, strings, scripts, docs. Two
  declared exceptions: `AI-VL-core/FIX.txt` and `robot-splunk-docs/*.md`.
- **`grep` here is not grep.** It is `ugrep --ignore-files`, so it respects `.gitignore` — and
  the umbrellas gitignore their child repos. A recursive `grep -r` from `~/Desktop` returns
  **zero hits inside the three AI-VL app repos**. For any verification sweep use
  `/usr/bin/grep -r`.

## Read these

| For | Read |
|---|---|
| The engineering standard — security, latency, tests, layout, with the incident behind each rule | `.claude/skills/cr/references/standard.md` |
| What is done, what is pending, and how to verify the setup still works | **`.claude/STATE.md`** |
| Reviewing uncommitted work across all repos | the `/cr` skill |
| Where things are in the code | the `codebase-memory` graph (`get_architecture`, `search_graph`) — all 11 repos, refreshed automatically |

Before changing anything in the transport layer, read
`AI-VL-ecosystem/docs/TRANSPORT_SDK_VS_ROS2.md`: what runs today is the ROS2 transport, which
is the reverse of the recorded decision.
