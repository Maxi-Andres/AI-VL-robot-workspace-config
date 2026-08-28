#!/usr/bin/env bash
# Test-coverage map for the whole workspace. READ IT, do not gate on it.
#
#   ~/Desktop/.claude/coverage.sh              # the table
#   ~/Desktop/.claude/coverage.sh --missing    # + the uncovered line ranges
#   ~/Desktop/.claude/coverage.sh --html       # + a browsable report per repo
#
# WHY THIS IS NOT A CI GATE. The JaCoCo habit is a threshold in the build ("fail under 80%").
# That is wrong for this codebase, and not by a little: `robot_executor_service.py` is 781
# statements at 0%, so any global threshold would either fail every build or force tests
# written to execute lines rather than to catch defects. The workspace standard is "every test
# names the defect it catches" — a percentage target rewards the opposite.
#
# What coverage IS good for here: knowing what is unprotected BEFORE refactoring it. That is a
# question you ask on demand, not on every push.
#
# `coverage` is not a repo dependency on purpose — it is installed into a throwaway venv under
# this directory so no repo's environment changes. Delete .covenv to reset.
set -uo pipefail   # NOT -e: a repo with no suite must not abort the sweep

cd "$(dirname "$0")/.."   # ~/Desktop
ROOT="$PWD"
COVENV="$ROOT/.claude/.covenv"
DATA="$ROOT/.claude/.coverage-data"
MODE="${1:-}"

if [ ! -x "$COVENV/bin/python" ]; then
  echo "[coverage] creating the throwaway venv (once)…" >&2
  python3 -m venv "$COVENV" || { echo "python3 -m venv failed" >&2; exit 1; }
  "$COVENV/bin/pip" -q install coverage pytest || exit 1
fi
PY="$COVENV/bin/python"
mkdir -p "$DATA"

# repo path : --source for coverage (the code we own, never tests or vendor trees)
TARGETS=(
  "unitree_ros2/robot_executor:."
  "unitree_ros2/robot_camera_bridge:."
  "robot-ecosystem/robot-command-relay:."
  "robot-ecosystem/robot-video-pipeline:robot"
  "robot-ecosystem/robot-telemetry-agent:."
  "AI-VL-ecosystem/AI-VL-backend:."
  "AI-VL-ecosystem/AI-VL-core:."
)

printf '\n%-34s %8s %8s %7s\n' "REPO / FILE" "STMTS" "MISS" "COVER"
printf '%s\n' "------------------------------------------------------------------"

for entry in "${TARGETS[@]}"; do
  repo="${entry%%:*}"; src="${entry##*:}"
  [ -d "$ROOT/$repo" ] || { printf '%-34s %s\n' "$(basename "$repo")" "(missing)"; continue; }

  # `--source` (not just --include) is the whole point: without it, coverage reports only the
  # files the tests happened to IMPORT, so a 781-line module nobody touches shows up as
  # absent rather than as 0%. That absence is exactly what you need to see.
  df="$DATA/$(basename "$repo").coverage"
  ( cd "$ROOT/$repo" \
    && "$PY" -m coverage run --source="$src" --data-file="$df" -m pytest -q >/dev/null 2>&1 )

  echo "── $repo"
  args=(report --data-file="$df" --omit='*/tests/*,*/.venv/*,*/conftest.py')
  [ "$MODE" = "--missing" ] && args+=(--show-missing)
  # `coverage report` writes "No data to report." to stderr and nothing to stdout when the
  # repo has no suite, so an empty body — not a missing data file — is the signal.
  out=$( cd "$ROOT/$repo" && "$PY" -m coverage "${args[@]}" 2>/dev/null | sed '1d' )
  if [ -z "$(printf '%s' "$out" | tr -d '[:space:]-')" ]; then
    echo "   NO SUITE — nothing measured. Green in CI because there is nothing to run."
    continue
  fi
  printf '%s\n' "$out" | sed 's/^/   /'
  if [ "$MODE" = "--html" ]; then
    ( cd "$ROOT/$repo" && "$PY" -m coverage html --data-file="$df" \
        -d "$DATA/html-$(basename "$repo")" >/dev/null 2>&1 )
    echo "   html: $DATA/html-$(basename "$repo")/index.html"
  fi
done

cat <<'NOTE'

------------------------------------------------------------------
How to read this:
  0%   the tests never even import the file. No safety net at all — the number to look at
       before touching it.
  low  a module whose pure layer is tested and whose I/O layer is not. Normal here.
  high only for the pure, defect-tested layers (command resolution, JPEG framing).

Coverage measures what ran, never whether it asserted anything. A file at 80% with weak
assertions is worse than one at 30% whose tests each name a defect.
NOTE
