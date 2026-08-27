---
name: cr
description: >-
  Code review across the whole workspace — all 11 repos in ~/Desktop, not just AI-VL.
  Discovers uncommitted changes in every repo (the two umbrellas, their children, and the
  robot transport code inside the unitree_ros2 fork), then reviews each against the shared
  engineering standard: hard rules, security, latency and backpressure, architecture,
  duplication, clean code, layout and tests. Reports findings grouped by repo, ranked by
  severity — it does NOT commit or edit. Invoke with `/cr` (optionally `/cr <repo>` or
  `/cr staged` to scope).
---

# /cr — workspace code review

Review **uncommitted** work before the user commits. Read-only: report findings; never
`git commit`/`git push`, and don't edit files unless the user explicitly asks for fixes
afterward.

## Scope (args)

- `/cr` — every repo with uncommitted changes.
- `/cr <repo>` — only that repo (e.g. `/cr robot-command-relay`).
- `/cr staged` — only staged changes in each repo.

## 1. Discover the changes

The workspace is two umbrellas with independent child repos, plus two vendors. Discover
rather than hardcode — the previous version of this skill listed four repos by name and
therefore never reviewed the code that moves robots:

```bash
cd ~/Desktop
for gitdir in $(find . -maxdepth 3 -name .git -type d); do
  repo="${gitdir%/.git}"
  printf '%s: ' "$repo"; git -C "$repo" status --porcelain | wc -l
done
```

Then per repo with changes:

```bash
git -C <repo> diff              # unstaged
git -C <repo> diff --cached     # staged
```

Untracked files have no diff base — read them in full. List up front which repos have
changes and what files, so the user sees the scope before the findings.

**Skip `unitree_sdk2` entirely** — pristine vendor. In `unitree_ros2`, review only
`robot_executor/` and `robot_camera_bridge/`; the rest is Unitree's.

## 2. Read enough to judge

Read the changed regions plus enough surrounding code to know whether a rule applies. Note
each file's repo and tier — the standard holds the robot tier to a higher bar, and a rule
about blocking a producer thread means nothing in a CLI and everything in the camera bridge.

## 3. Review against the standard

Load **`references/standard.md`** — that is the review standard, with the severity legend and
the evidence behind each rule. Apply its §10 order: hard rules, security, latency and
backpressure, architecture and duplication, clean code and layout, tests.

Two things to actually do rather than assume:

- **Duplication**: query the codebase-memory graph over the affected repo
  (`search_graph`, `get_architecture`) before claiming something is or isn't already
  implemented. All 11 repos are indexed and refresh automatically.
- **Verification sweeps**: use `/usr/bin/grep -r`. The environment's `grep` is
  `ugrep --ignore-files` and silently skips gitignored directories — which includes the three
  AI-VL app repos, because the umbrella gitignores them.

## 4. Report

Grouped **by repo**, most-severe first:

- `path:line` — **[blocker|warn|nit]** one-line issue → concrete fix.

End with a per-repo verdict ("robot-command-relay: 1 blocker, 2 warns" / "AI-VL-core:
clean") and an overall summary. If a repo is clean, say so. Do not restate the diff — only
what needs attention.

If a finding is a repeat of something the standard already cites as evidence, say so: it
means a known defect is spreading rather than being fixed.

## Complement

`/code-review` (built-in) is heavier and adversarial on a single diff — use it when the
change is risky. `/cr` is the workspace-wide gate that enforces *these* conventions. Use both
when the change touches the control path.
