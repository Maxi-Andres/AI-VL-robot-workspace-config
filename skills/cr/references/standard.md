# Engineering standard — robot + AI-VL workspace

The review standard for **all 11 repos** in `~/Desktop`. Every rule below is grounded in
something that actually happened in this codebase; the citation after each one is the
evidence, not decoration. A rule with no evidence behind it does not belong here.

Severity: **[blocker]** breaks a hard rule or is a real bug · **[warn]** should fix ·
**[nit]** optional polish.

Supersedes `AI-VL-ecosystem/.claude/skills/cr/references/best-practices.md`, which covered
4 of the 11 repos and had drifted from the code.

---

## 0. Scope

| Repo | Tier | Runs on |
|---|---|---|
| `AI-VL-ecosystem` | launchers + docs | workstation |
| `AI-VL-core` | iacore: YOLO, VLM, STT, TTS | workstation (GPU) |
| `AI-VL-backend` | gateway: HTTP/WS, the only public surface | workstation |
| `AI-VL-frontend` | SPA | browser / phone |
| `unitree_ros2` (`robot_executor`, `robot_camera_bridge`) | robot transport | workstation, in a container |
| `robot-video-pipeline` | video: capture → stream → NVR | **split**: robot + workstation |
| `robot-telemetry-agent` | telemetry, read-only | **robot** |
| `robot-command-relay` | the only remote path that can move the robot | **robot** |
| `robot-splunk-docs` | engineering record | nothing |
| `robot-ecosystem`, `unitree_sdk2` | umbrella / vendor | — |

**Vendor code is out of scope.** `unitree_sdk2` is pristine upstream: never patch it, never
review it. In `unitree_ros2`, only `robot_executor/` and `robot_camera_bridge/` are ours.

**The robot tier is held to a higher bar than the workstation tier.** Code that runs on the
robot cannot be restarted by hand, shares a machine with the control stack, and may be on a
link that drops. When a rule below says *robot tier*, it is not optional.

---

## 1. Hard rules

- **[blocker] Never `git commit` / `git push`.** Not in code, not in scripts, not by
  running it. The user commits. *(standing project rule)*
- **[blocker] English in every repo** — comments, docstrings, identifiers, user-facing
  strings, config keys, shell/PowerShell. Two declared exceptions and no others:
  `AI-VL-core/FIX.txt`, and `robot-splunk-docs/*.md`, which is Spanish planning narrative on
  purpose. *(4 Spanish debug strings still sit in `ControlPage.tsx:280-312`)*
- **[blocker] Fail safe, not fail open.** A missing field, an absent config value or an
  unparseable input must select the *safest* behavior, never the most permissive.
  *(`SAFE_MODE` defaulted to `False`, so a client omitting `safe_mode` unlocked skills that
  can drop the robot; `move` without `continuous` defaulted to unbounded motion, disabling
  the dead-man)*
- **[blocker] No generic passthrough on the control path.** No endpoint may forward an
  arbitrary `api_id`, opcode or command string to the robot. Verbs are an explicit
  allowlist, translated — never relayed. *(`command_sender.cpp` is the reference
  implementation: a `std::map` of named verbs and nothing else)*
- **[blocker] The network boundary.** The three AI-VL apps talk by URL and port, never by
  file path; no cross-app import, no shared filesystem reference. Frontend talks only to the
  backend; the backend reaches iacore only via `IACORE_URL`. The robot repos talk to the
  workstation only over HTTP. *(this is what makes each tier independently deployable, and
  it is why some duplication is forced — see §5)*
- **[blocker] Docs and code agree, or the code wins and the doc gets fixed.** A comment that
  contradicts the line under it is worse than no comment. *(the executor's docstring claimed
  "SAFE_MODE default on" twelve lines above `SAFE_MODE = False`; the relay's docstring
  claimed it binds to the VPN address while it bound `0.0.0.0`; the launchers advertised a
  `/monitor` route deleted months earlier)*

---

## 2. Security

- **[blocker] Every service that can move the robot or expose operational data requires a
  token.** No exceptions for "it's only on the LAN" — there is a tailnet, and ufw is off on
  purpose because it breaks DDS, so there is no network-level fallback.
  *(gateway, executor, camera bridge, iacore, mediamtx and Frigate were all reachable on
  `0.0.0.0` with no credential)*
- **[blocker] Authenticate every method, not just the one you were thinking about.**
  *(the relay validated the Bearer token in `do_POST` and not in `do_GET`, so an
  unauthenticated `/health` returned the Splunk HEC URL, the index, the video publish host
  and the DDS interface)*
- **[blocker] Never log, print or echo a secret** — not even in an error message, not even
  when it is malformed. Report length and shape. *(`hec_shipper.py:145` printed the whole
  HEC token via `{HEC_TOKEN!r}` when it contained whitespace)*
- **[warn] Compare secrets in constant time** — `hmac.compare_digest`, not `==`.
- **[warn] Bind to the narrowest interface that works**, and make the default the narrow
  one. A service that must be broad requires an explicit opt-in flag.
- **[warn] Bound every input.** Request bodies, frame buffers, queue depths and spool
  directories all need a ceiling and a defined behavior at the ceiling.
  *(`/detect`, `/vlm` and `/transcribe` read unbounded bodies into memory; two MJPEG parsers
  grow their buffer forever if no EOI marker arrives)*
- **[warn] Verify TLS by default.** A self-signed lab certificate is a reason to pin a CA,
  not to set `verify=False` and forget. *(`VERIFY_TLS` defaults to 0 while the HEC token
  crosses Starlink)*
- **[warn] Least privilege for containers.** `privileged: true`, host networking and a
  mounted docker socket are three separate grants; take only the ones the process needs. DDS
  needs host networking, not root-equivalent. *(the executor runs in Unitree's devcontainer
  with all three)*
- **[nit] Secrets live outside the repo tree** — `~/.relay_token`, `~/.splunk_hec_token`.
  This is already right everywhere; keep it that way, and keep `.env` gitignored while
  `.env.example` is committed.

---

## 3. Latency and backpressure

This is the section that is specific to this project. Robots and video are the workload, and
in both the enemy is the same: a slow consumer reaching back and throttling a producer.

- **[blocker] Never block a producer thread on a consumer.** Not the ROS callback thread,
  not the DDS reader, not the capture loop. Hand off through a bounded queue and let the
  consumer starve. *(the camera bridge calls `ws.send_binary()` while holding its lock on the
  ROS callback thread, with the socket in blocking mode — a stalled TCP connection freezes
  the whole bridge, including its own `/status` and `/stop`. The MJPEG server gets this
  right: a `nvr_writer` thread is "the only thing allowed to block on stdout")*
- **[blocker] Drop, never queue, for anything a human watches.** Live video and detections
  keep exactly one frame of state; a slow viewer skips frames and never delays another.
  *(`Latest` in `mjpeg_server.py` and `_put_latest` in `app.py` are the two reference
  implementations — "deliberately not a queue: a queue is how latency accumulates")*
- **[warn] An encoder needs cadence; a decoder tolerates drops.** Feed a recording branch a
  fixed interval, not leftovers. *(dropping oldest-on-full fed H.264 an irregular 27% of
  frames, the FLV timestamps jumped, and Frigate refused to start: "no frames have been
  received")*
- **[warn] Do expensive per-frame work once, not once per consumer, and never on the capture
  path.** *(resizing inline in `pump()` dropped capture from 3.2 to 2.3 fps; moving it to a
  worker thread with a second slot fixed it)*
- **[warn] The live path must not traverse the recording path.** *(routing the live view
  through encode → RTMP → mediamtx → Frigate added ~7 s, because an NVR buffers on purpose.
  The `:8093` MJPEG tee exists to bypass it)*
- **[warn] Prefer passthrough to re-encode.** If the source already emits JPEG, forward the
  bytes. *(`_reprocess()` returns the original buffer untouched at `quality=0` and
  `resolution=native` — the fast path is the default)*
- **[warn] Keep one hot client per hot path.** A persistent HTTP client with explicit
  timeouts, created once. *(the gateway creates 9 `AsyncClient`s per request on the executor
  and camera routes, paying a TCP handshake per teleop command at 150 ms cadence)*
- **[blocker] Bounded motion, always.** A movement command carries a deadline and is
  refreshed; if refreshes stop, the robot stops. Continuous motion is opt-in and explicit.
  *(`DEADMAN_MS=1500`, `DURATION_S=0.4` at a 150 ms cadence — the invariant the whole teleop
  design rests on)*
- **[warn] Commands that supersede each other need an order.** Concurrent HTTP requests
  arrive in any order; the newest must win and stale ones must be discarded.
  *(a `move` issued before a `stop` could land after it and restart motion for up to 400 ms)*
- **[nit] State the budget in the code.** Where a number matters, write it and where it came
  from. This codebase already does this unusually well — keep it.

---

## 4. Architecture

- **[blocker] One source of truth per contract, per tier.** Within a repo, a shape is
  declared once. `vlm_common.py` for iacore's shared logic, `types.ts` for the browser
  contract, `config.ts` for the backend URL, the command modules for verbs and clamps.
- **[warn] Abstract the transport, not the behavior.** Robot access goes through the
  `RobotTransport` interface; a new transport is a new implementation, and nothing above it
  changes. *(the interface exists and is honored — `Go2Ros2Transport`, `G1Ros2Transport`,
  `RelayTransport` — which is what makes the SDK migration additive rather than a rewrite)*
- **[warn] Shared behavior belongs in the base class, not copied into each implementation.**
  *(the dead-man loop is written three times, 70% identical between the two ROS2 transports.
  Only "publish a velocity" and "publish a stop" differ, and only those belong in a subclass)*
- **[warn] The service layer holds no robot-specific constants.** `api_id`s, topic names and
  skill tables live in the per-robot module.
- **[warn] Decisions get recorded where the code is, and the record wins.** An architectural
  choice that contradicts the written decision must either change the code or change the
  record, with the reason. *(the decision said "SDK now, ROS2 when Nav2 arrives" and the
  implementation did the reverse; it took a session to reconstruct why —
  `docs/TRANSPORT_SDK_VS_ROS2.md`)*
- **[nit] Prefer adding a branch to an existing seam over adding a new seam.**

---

## 5. Reuse and duplication

- **[warn] Before writing a helper, look for it.** Use the codebase-memory graph
  (`search_graph`, `get_architecture`) over the 11 indexed repos, not memory.
- **[warn] Duplication inside one repo is a defect.** There is no boundary excuse.
  *(`_load_dotenv` and `_as_bool` are copied between the executor and the camera bridge;
  `_clamp` is byte-identical in `go2_commands.py` and `g1_commands.py`)*
- **[warn] Duplication across repos is sometimes forced — then it needs a test, not a
  shared module.** The network boundary forbids sharing code between tiers, so the four
  request models declared identically in `app.py` and `service.py` cannot be merged. Guard
  them with a contract test instead. *(adding a `seq` field to fix the command race would
  have been silently dropped by Pydantic in the backend)*
- **[warn] When you must duplicate, cross-reference both copies in a comment**, so the next
  fix finds the sibling. *(the two MJPEG parsers share a missing buffer cap — the same bug,
  twice)*
- **[warn] Three copies is the hard limit for anything on the control path.** At the second
  copy, factor it.

---

## 6. Clean code and smells

- **[warn] Delete, don't comment out.** Git remembers. *(`setupOLD.sh`: 12 lines, zero
  references; `backup_config.yaml`, which the project's own IP inventory lists as unused)*
- **[warn] A file that is built but on no runtime path says so in its README.**
  *(`go2_h264_stream.cpp` is compiled by `build.sh` and executed by nothing)*
- **[warn] Comment the why, never the what.** This codebase is unusually good at this — the
  `-vsync cfr` note, the SRT-vs-RTMP bisect, the `SportClient` static-init segfault. That is
  the bar.
- **[warn] No debug output outside a flag.** *(all current `console.log` calls sit behind
  `if (debug)` / `PAD_DEBUG` — keep it)*
- **[warn] Catch specific exceptions**, never bare `except:`; use `logging` in services and
  `print` only in CLIs. *(iacore complies: zero prints in `service.py`)*
- **[warn] Type the boundary.** Strict TS with no `any`; Pydantic models, not `dict`, for
  request bodies. *(both already hold — zero `any` in the frontend)*
- **[warn] Every effect and every subscription cleans up.** Sockets, listeners, streams,
  timers, `AbortController`s.
- **[warn] Cancel in-flight fetches on unmount.** *(five fetch-on-mount hooks lack an
  `AbortController` while `LivePage` uses one correctly for the long VLM calls — the
  discipline exists and is applied unevenly)*
- **[warn] Guard shell scripts**: `set -euo pipefail` in anything that installs or builds,
  and check external commands exist before using them. Supervisors that must survive a
  failing child are the documented exception. *(three launch scripts in the fork lack it)*
- **[nit] No `TODO`/`FIXME` left behind** — currently zero across ~14k lines. Keep it at
  zero: open an item in the plan instead.

---

## 7. Tests that test something

A test exists to catch a specific bug. **If you cannot name the bug it catches, delete it.**

**Banned outright:** `assert True`; asserting a value against itself; a test with no
assertion; asserting on a mock you wrote in the same file (that tests the mock); snapshot
tests of formatting; tests that only exercise a getter.

**The bar, in one sentence:** break the line the test covers and the test must go red. If it
stays green, it was decoration.

- **[blocker] Test the failure mode, not just the happy path.** The happy path is what you
  already ran by hand. What breaks in the field is the timeout, the malformed body, the
  reconnect, the stale command.
- **[warn] Table-driven for anything with a catalog.** Verb resolution, clamps, the
  dangerous-skill set: one row per case, including the out-of-range and missing-field rows.
- **[warn] Assert the invariant, not the clock.** Never assert wall-clock timing — assert
  that the queue never exceeded N, that the oldest item was the one dropped, that a stale
  sequence number was refused. Timing assertions are how a suite becomes flaky and then
  ignored.
- **[warn] Robot tests run with `DRY_RUN=true` and touch no DDS.** The executor already
  supports this; it is the seam that makes the control path testable without a robot.
- **[warn] Contract tests over mirrored declarations.** Where the boundary forces the same
  shape into two tiers, a test compares the two live schemas. Both services are FastAPI and
  expose `/openapi.json`.
- **[warn] No network in unit tests.** Use the ASGI transport in-process for FastAPI, a fake
  socket for the WS paths, and byte fixtures for the parsers.
- **[nit] Name the test after the bug**: `test_stale_move_is_discarded_after_stop`, not
  `test_move_2`.

### The first suite, in priority order

Each entry names the defect it would have caught:

1. **`safe_mode` omitted → dangerous skill refused.** Catches the fail-open default.
2. **A `move` with a lower `seq` than the last applied → refused; any `stop` wins.** Catches
   the command race, and the barrier that covers two simultaneous drivers.
3. **Backend request models match iacore's `/openapi.json`.** Catches a field silently
   dropped at the gateway.
4. **`move` without `continuous` → bounded.** Catches the second fail-open default.
5. **MJPEG parser: frame split across chunks, garbage before SOI, no EOI within the cap.**
   Catches the unbounded buffer, in both copies.
6. **Verb resolution per robot, table-driven, including clamps at and beyond the limit.**
   Catches divergence between the two command catalogs.
7. **Frontend: the detection socket keeps exactly one frame in flight.** Catches the
   invariant the whole live path depends on.

---

## 8. Directory layout

Segmentation follows the tier, and every repo states its own layout in its README.

**Python service** (`AI-VL-backend`, `AI-VL-core`)

```
service.py | app.py     the ONLY networked surface — routes and validation, no logic
src/                    the logic, importable and independently testable
  *_common.py           shared helpers; the single source of truth per concern
tests/                  mirrors src/, plus contract tests for the tier boundary
.env.example            every variable the service reads, documented
```

A single-file service is fine — the backend's `app.py` is deliberate — up until a helper
would remove repeated shape. At three copies, extract a module.

**Frontend** (`AI-VL-frontend`)

```
src/pages/              containers: own the state, wire the hooks
src/components/{live,control,layout,ui}/   presentational; never import from api/
src/hooks/              one concern per hook, named use*, typed return
src/lib/                pure helpers, no React
src/api/                every network call, in one place
src/types.ts            the backend contract
src/config.ts           the only place a URL is resolved
tests/                  next to what they test
```

**Robot repo** (`robot-telemetry-agent`, `robot-command-relay`, `robot-video-pipeline`)

```
src/                    C++ that talks to the SDK
*.py                    the stdlib-only Python layer (the robot has Python 3.8)
robot/                  the half that is deployed ON the robot, when the repo spans both
systemd/                unit files, paths matching the documented deploy location
build.sh                one target per binary, no cmake
.env.example            committed; the real .env gitignored
tests/                  runs on the workstation, no DDS
```

**Rules that hold everywhere:** no build artifacts committed; no runtime-written file
tracked *(`unitree_ros2/dds.env` is written by `POST /dds` and is in git)*; no large binary
assets *(1.5 MB of JPEGs in `AI-VL-core/fotos/`)*; vendored third-party content carries a
provenance note *(~5.000 lines of URDF and meshes in `go2_visualization/`)*; and a
`README.md` that a stranger can follow to a running system.

---

## 9. Tooling

- **Formatting is NOT enforced.** `ruff format` was tried and rejected: this codebase is
  hand-formatted with deliberate comment alignment, and running the formatter would produce
  one enormous diff across working robot code for zero behavioral gain. `ruff check` (lint)
  is enforced; formatting is the author's call. Revisit only as a deliberate, separate commit.
- **Lint**: `ruff` for Python, `eslint` + `typescript-eslint` for the frontend
  (absent today — there is a dead `eslint-disable` comment proving it), `clang-format` for
  the three C++ files.
- **Types**: `tsc -b --noEmit` on every frontend change. Already passes; keep it green.
- **Tests**: `pytest` (+ `pytest-asyncio`, `httpx` ASGI transport) for the Python tiers,
  `vitest` for the frontend. Installed.
- **The commit gate**: `pre-commit` is installed in every repo with code. It runs the fast
  checks — whitespace, merge markers, **private-key detection**, a 512 KB file-size cap, lint,
  and the test suite — and **blocks the commit** on failure. Verified: a bare `except` or a
  private key in a staged file both return rc=1. A repo with no suite yet is not blocked
  (pytest's exit 5 is tolerated); a repo whose suite breaks is.
- **CI**: one `.github/workflows/ci.yml` per repo — lint, test, and for the frontend also
  typecheck and build. The robot repos run on `ubuntu-22.04` with **Python 3.8**, the version
  the Jetson actually has, so CI cannot pass syntax the robot would reject.
- **Dependency audit**: `pip-audit` in CI, advisory rather than blocking — a new CVE
  disclosure must not stand between you and a hotfix.
- **The graph**: `codebase-memory-mcp` covers all 11 repos and refreshes on session
  start/stop via `.claude/hooks/reindex-if-needed.sh`. Query it before assuming.
- **Searching**: `grep` in this environment is `ugrep --ignore-files` and **silently skips
  gitignored directories**, including the three AI-VL app repos that the umbrella ignores.
  For any verification sweep use `/usr/bin/grep -r`. *(a rename sweep reported "0 stale
  references" while five sat in `RobotConfigPage.tsx`)*

---

## 10. Review procedure

For each repo with changes: read the diff, then check in this order. Stop at the first
blocker and report it.

1. **Hard rules** (§1) — language, commit discipline, fail-safe, no passthrough, the network
   boundary, docs-vs-code.
2. **Security** (§2) — for anything on the control path or exposing data.
3. **Latency and backpressure** (§3) — for anything touching video, frames, teleop or DDS.
4. **Architecture** (§4) and **duplication** (§5) — query the graph, don't guess.
5. **Clean code** (§6) and **layout** (§8).
6. **Tests** (§7) — does the change come with a test that could fail? If the change fixes a
   bug, the test must reproduce that bug.

Report as `path:line — [blocker|warn|nit] issue → concrete fix`, grouped by repo,
most-severe first. End with a per-repo verdict. Never commit; never edit unless asked.
