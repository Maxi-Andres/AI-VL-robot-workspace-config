# AI-VL-robot-workspace-config

The shared configuration and engineering standard for the robot + AI-VL workspace. **This
repo is the `.claude` directory of the workspace**, so it gets cloned into position rather
than cloned next to the code — note the explicit destination, which is what makes the repo
root land as `.claude`:

```bash
git clone https://github.com/Maxi-Andres/AI-VL-robot-workspace-config.git ~/Desktop/.claude
bash ~/Desktop/.claude/install.sh
```

It exists because the engineering standard for 11 repos was living as loose files in a
directory no repo tracked — one wiped machine and it was gone.

## What the workspace looks like

```
~/Desktop/
├── .claude/                ← THIS REPO (config, standard, review skill, hooks)
├── .mcp.json               ← symlink to .claude/mcp.json, created by install.sh
├── AI-VL-ecosystem/        umbrella: launchers + docs
│   ├── AI-VL-core/           iacore — YOLO, VLM, STT, TTS
│   ├── AI-VL-backend/        gateway — the only public surface
│   └── AI-VL-frontend/       SPA
├── robot-ecosystem/        umbrella
│   ├── robot-video-pipeline/    capture → stream → NVR
│   ├── robot-telemetry-agent/   telemetry to Splunk, read-only, runs ON the robot
│   ├── robot-command-relay/     the only remote path that can move the robot
│   └── robot-splunk-docs/       engineering record
├── unitree_ros2/           own fork: robot_executor + robot_camera_bridge
└── unitree_sdk2/           pristine vendor SDK — never patch
```

11 git repos. The umbrellas gitignore their children, so each child is independent.

## What's in here

| Path | What it is |
|---|---|
| `skills/cr/references/standard.md` | **The engineering standard.** Every rule cites the incident in this codebase that motivated it. Read this before writing code. |
| `skills/cr/SKILL.md` | `/cr` — the workspace-wide review gate. Discovers all 11 repos, reviews against the standard. |
| `hooks/reindex-if-needed.sh` | Keeps the `codebase-memory` graph fresh. Discovers repos dynamically; re-indexes only what changed (~0.2 s per repo, nothing when nothing changed). |
| `settings.json` | Registers the hook on SessionStart/Stop and enables the MCP server. |
| `mcp.json` | The `codebase-memory-mcp` declaration, linked to `../.mcp.json` by `install.sh`. |

## The two things that bite

**`grep` here is not grep.** It is a shell function that runs `ugrep --ignore-files`, so it
**respects `.gitignore`** — and the umbrellas gitignore their child repos. A recursive
`grep -r` from `~/Desktop` silently returns zero hits inside the three AI-VL app repos. For
any verification sweep use `/usr/bin/grep -r`. This already caused a rename sweep to report
"0 stale references" while five sat in a file it never opened.

**Config is scoped to where you open the session.** `.mcp.json` and `.claude/settings.json`
are read from the directory Claude Code starts in. Open from `~/Desktop`, not from a
sub-repo, or the graph and the review skill are not loaded. The previous setup had both
inside `AI-VL-ecosystem/`, which is why the graph sat 45 days stale with 4 of 11 repos
indexed.

## The commit gate

Every repo with code has `pre-commit` installed, so a bad commit is refused before it exists:

| Check | Blocks on |
|---|---|
| `detect-private-key` | a key or token pasted into a tracked file |
| `check-added-large-files` | anything over 512 KB (model weights, media) |
| `ruff check` | lint; the robot repos also reject 3.9+ syntax the Jetson cannot run |
| `pytest` / `vitest` + `tsc` | a broken suite or a type error |

On a new machine: `pre-commit install` in each repo. Run it over everything with
`pre-commit run --all-files`. Formatting is deliberately **not** enforced — see §9 of the
standard for why.

CI mirrors the gate per repo in `.github/workflows/ci.yml`, plus an advisory `pip-audit`.

## Tools this workspace expects

```bash
# Python tooling, in a dedicated venv so PEP 668 stays happy
python3 -m venv ~/.local/share/dev-tools
~/.local/share/dev-tools/bin/pip install ruff pre-commit pip-audit
for t in ruff pre-commit pip-audit; do ln -sf ~/.local/share/dev-tools/bin/$t ~/.local/bin/$t; done

# Frontend + duplication detection
bun add -g jscpd            # multi-language copy/paste detector
```

## Conventions

- **English in every repo** — code, comments, identifiers, strings, scripts, docs. Two
  declared exceptions: `AI-VL-core/FIX.txt` and `robot-splunk-docs/*.md` (Spanish planning
  narrative, on purpose).
- **Never `git commit` or `git push`** from an agent. The user commits.
- The full rule set, with severities and evidence, is `skills/cr/references/standard.md`.
