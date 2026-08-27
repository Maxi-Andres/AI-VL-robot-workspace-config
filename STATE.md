# State and next steps

Last updated **2026-08-27**. Read this at the start of a session; re-run §1 if anything looks
off, and update the checkboxes in §3 as they land.

---

## 1. Verify the setup still works

Run this first. It is the whole health check and takes a few seconds.

```bash
cd ~/Desktop

# Tools (jscpd MUST be called as `bunx jscpd` — bun's global shim execs node, which is absent)
for t in ruff pre-commit pip-audit codebase-memory-mcp bun; do printf '%-22s %s\n' "$t" "$($t --version 2>&1|head -1)"; done
AI-VL-ecosystem/AI-VL-core/.venv/bin/pytest --version
(cd AI-VL-ecosystem/AI-VL-frontend && bunx eslint --version && bunx vitest --version)

# Lint: all six Python repos and the frontend must be clean
for r in AI-VL-ecosystem/AI-VL-core AI-VL-ecosystem/AI-VL-backend \
         robot-ecosystem/robot-telemetry-agent robot-ecosystem/robot-command-relay \
         robot-ecosystem/robot-video-pipeline unitree_ros2; do
  printf '%-24s ' "$(basename $r)"; (cd $r && ruff check --no-cache -q && echo OK)
done
(cd AI-VL-ecosystem/AI-VL-frontend && bunx eslint src && bun run typecheck)

# Tests: 24+2 and 6+2, all green
(cd unitree_ros2/robot_executor && python3 -m pytest -q)
(cd robot-ecosystem/robot-command-relay && python3 -m pytest -q)

# The commit gate, exactly as git invokes it (NOT --all-files: that skips untracked files
# and will report a false pass on new test files)
for r in AI-VL-ecosystem/AI-VL-{core,backend,frontend} unitree_ros2 \
         robot-ecosystem/robot-{telemetry-agent,command-relay,video-pipeline}; do
  (cd $r && git add -A && pre-commit run >/dev/null 2>&1; printf '%-24s rc=%s\n' "$(basename $r)" $?)
done

# The graph
.claude/hooks/reindex-if-needed.sh && echo "reindex OK"
codebase-memory-mcp cli list_projects '{}' 2>/dev/null | tail -1

# CI in the cloud (public repos, no token needed). Check the budget FIRST: unauthenticated
# calls are capped at 60/hour and an exhausted quota makes the loop below print NOTHING —
# silence is a spent quota, not a failed workflow.
curl -s https://api.github.com/rate_limit | python3 -c "import sys,json;d=json.load(sys.stdin)['resources']['core'];print('API calls left:',d['remaining'],'of',d['limit'])"

for repo in AI-VL-core AI-VL-backend AI-VL-frontend robot-video-pipeline \
            robot-telemetry-agent robot-command-relay unitree_ros2; do
  curl -s "https://api.github.com/repos/Maxi-Andres/$repo/actions/runs?per_page=1" \
   | python3 -c "import sys,json;r=json.load(sys.stdin)['workflow_runs'][0];print(f\"$repo {r['conclusion']}\")" \
   || echo "$repo: no answer (quota?)"
done
```

Installing `gh` and authenticating raises that cap to 5.000/hour and makes
`gh run list -R Maxi-Andres/<repo>` a one-liner. Worth it if this check gets run often.

**Two things this cannot check.** The MCP server and the SessionStart hook are loaded when a
session starts, so a session already running cannot confirm them:

- `/mcp` must show `codebase-memory-mcp` **connected**. First time in a new session it asks
  for approval — accept once.
- If the reindex hook does not fire on start, open `/hooks` once (that reloads the config) or
  restart. The script itself is verified above.

---

## 2. What is in place (2026-08-27)

- **Standard**: `.claude/skills/cr/references/standard.md` — 10 sections covering hard rules,
  security, latency and backpressure, architecture, duplication, clean code, tests, layout,
  tooling and the review procedure. Every rule cites the incident in this codebase behind it.
  Supersedes the old AI-VL-only one, which is now banner-marked.
- **Review gate**: `/cr` discovers all 11 repos dynamically. The old AI-VL-scoped `/cr` now
  loads this same standard, so the two paths cannot diverge.
- **Lint**: `ruff.toml` per repo. The three robot repos pin `target-version = "py38"` and
  enable `FA`, so the linter refuses 3.9+ syntax the Jetson cannot run. `eslint` flat config
  in the frontend with the react-hooks rules. All clean.
- **Commit gate**: `pre-commit` in the 7 repos with code — whitespace, merge markers,
  private-key detection, a 512 KB size cap, lint, tests. Verified to return rc=1 on a bare
  `except` and on a private key, rc=0 on the real tree. Formatting is deliberately NOT
  enforced (standard §9 explains why).
- **CI**: `.github/workflows/ci.yml` per repo, 7/7 green. The robot repos run on
  `ubuntu-22.04` with **Python 3.8** — the version the Jetson has. This already earned its
  keep: it caught a `set[str]` annotation that passes on 3.14 and raises `TypeError` on 3.8.
- **Tests**: 30 tests, 4 strict xfails. Every test names the defect it catches.
- **Graph**: all 11 repos indexed, refreshed on session start/stop, ~0.12 s when nothing
  changed.

### The four strict xfails

They assert the CORRECT behavior for defects that are still open. `strict=True` means that
when the defect is fixed the test passes unexpectedly and **pytest fails**, telling you to
delete the marker. Fix the code, delete the marker — do not delete the test.

| Test | Defect |
|---|---|
| `test_move_without_continuous_is_bounded` (×2 robots) | finding P0-4: `continuous` defaults to `True`, disabling the dead-man |
| `test_rate_limiter_does_not_allow_double_the_budget_across_a_boundary` | fixed windows let 2× through at the boundary |
| `test_token_comparison_is_constant_time` | the relay compares its token with `==` |

---

## 3. Next, in order of what it buys

### Tests that need no robot — do these first

- [ ] **Contract test, backend ↔ iacore.** The four request models are declared identically in
  `app.py` and `service.py`, and nothing checks it. The boundary forbids sharing a module, so
  the fix is a test, not a refactor. Both are FastAPI and expose `/openapi.json`; alternatively
  each repo keeps a small committed contract JSON and asserts its own models against it.
  **This is the only pending item that prevents a future bug rather than cleaning up a past
  one** — adding `seq` for the command race would have been silently dropped by Pydantic.
- [ ] **MJPEG parser test.** Frame split across chunks, garbage before SOI, no EOI within the
  cap. Covers `camera_sources._read_stream` and `mjpeg_server.pump` — the same 20-line
  algorithm duplicated in two repos, both missing the buffer ceiling.
- [ ] **Frontend: one-frame-in-flight** on the detection socket. The invariant the whole live
  path rests on, and `vitest` is already wired with `--passWithNoTests`.

Four repos are currently green in CI *because they have no suite*, not because they are
tested: `AI-VL-core`, `AI-VL-backend`, `robot-telemetry-agent`, `robot-video-pipeline`.

### Safety (P0s from the security audit)

- [ ] **`SAFE_MODE` fail-safe** — `robot_executor_service.py:89` defaults to `False`, and
  `:1260` lets a request that omits the field pick the permissive path. Default `True` both
  places, and align the docstring at `:16` which already claims it.
- [ ] **`continuous` fail-safe** — `go2_commands.py:127`, `g1_commands.py:279`. Flip to
  `False`; the xfail test flips with it.
- [ ] **Token on the service boundary** — the executor and the camera bridge accept unauthenticated
  requests on `0.0.0.0`. Copy the relay's Bearer pattern. The four `# noqa: S104` comments mark
  exactly the places to fix; remove them as you go and ruff keeps the rule enforced.
- [ ] **Command sequence + stop barrier** — a `move` issued before a `stop` can land after it.
  Needs `seq` + `client_id` through all three tiers, which is what makes the contract test
  above worth having first.

### Quality (from the duplication audit)

- [ ] **Proxy helper in the gateway** — 9 per-request `httpx.AsyncClient`s in
  `app.py:227-396`, in near-identical try/except blocks. One helper plus two persistent
  clients in the `lifespan`. Also where the auth headers land, once.
- [ ] **Template method for the dead-man** — implemented three times in
  `robot_executor_service.py` (70% identical between the two ROS2 transports). Base class owns
  the loop, deadline, lock and thread; each transport implements only `_publish_velocity()` and
  `_publish_stop()`. `bunx jscpd unitree_ros2/robot_executor --min-lines 12 --min-tokens 60`
  reports it: 3 clones, 45 lines.
- [ ] **Shared helpers in the fork** — `_load_dotenv` and `_as_bool` are copied between the
  executor and the camera bridge; `_clamp` is byte-identical in the two command modules. Same
  repo, so a `common.py` breaks no boundary.
- [ ] **Five fetch-on-mount hooks without `AbortController`** — `useSpeech`, `useOptions`,
  `usePresence`, `CameraControls`, `NetworkControls`. `LivePage` does it right for the long
  VLM calls; the discipline exists and is applied unevenly.

### Housekeeping

- [ ] Delete `unitree_ros2/setupOLD.sh` (12 lines, zero references) and
  `robot-video-pipeline/frigate/config/backup_config.yaml` (the project's own IP inventory
  lists it as unused).
- [ ] Untrack `unitree_ros2/dds.env` — it is written at runtime by `POST /dds`, so every
  network change from the UI dirties the repo.
- [ ] Translate the four Spanish debug strings in `ControlPage.tsx:280-312` — a [blocker] by
  the workspace's own language rule.
- [ ] Note in `robot-video-pipeline/README.md` that `go2_h264_stream.cpp` is built but on no
  runtime path, so nobody mistakes it for part of the pipeline.
- [ ] Decide on `AI-VL-ecosystem/.mcp.json` and its `settings.local.json` hook: harmless while
  sessions open from `~/Desktop`, but opening from that directory loads a config that indexes
  only 4 of 11 repos.
- [ ] `AI-VL-frontend` sits on branch `feature/both-robots-same-tiem` while its three siblings
  are on `...same-time`. A typo that will bite when the PRs go up together.

### Bigger, its own session

- [ ] **Migrate the transport to the native SDK** — the full case, cost and order are written
  in `AI-VL-ecosystem/docs/TRANSPORT_SDK_VS_ROS2.md`. Additive and reversible: steps 1-3 leave
  both paths live and switchable from the Robot page; only step 5 removes anything.
- [ ] **Extract `robot_executor/` and `robot_camera_bridge/` from the vendor fork.** Blocked on
  the devcontainer: `run_executor.sh` resolves the ROS2 workspace as its own parent and the
  container mounts `..:/workspace`, so the mount and env have to be redesigned first.

---

## 4. Two audits, for the reasoning behind all of the above

Both are Artifacts, in Spanish, and cover different axes:

- **Security and correctness** (41 findings, phased plan): the control plane, the fail-open
  defaults, the command race, latency and supervision.
- **Duplication and best practices** (12 findings, measured): the three copies of the dead-man,
  the nine HTTP clients, the contract written three times, plus what is provably clean.

Ask the user for the links if they are not in the conversation.
