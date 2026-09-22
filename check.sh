#!/usr/bin/env bash
# check.sh — el health check del workspace, EJECUTABLE.
#
#   ~/Desktop/.claude/check.sh           herramientas + lint + tests + grafo   (rápido, local)
#   ~/Desktop/.claude/check.sh --net     + Splunk HEC y Frigate
#   ~/Desktop/.claude/check.sh --gate    + el gate de pre-commit (stagea y puede REESCRIBIR archivos)
#   ~/Desktop/.claude/check.sh --all     todo
#
# POR QUÉ EXISTE. Esto vivía como 40 líneas de shell dentro de `roadmap/PLATAFORMA.md` §8, y
# la prosa no se ejecuta: se pudre en silencio. El 2026-09-22, la primera vez que alguien lo
# corrió entero a mano, salieron dos defectos que llevaban semanas ahí:
#
#   * `python3 -m pytest` fallaba en `AI-VL-backend` — sus tests importan fastapi, que está en
#     el venv y no en el python del sistema. El bloque decía `python3` a secas para los seis
#     repos, y dos de los seis tienen venv.
#   * El conteo de tests del ROADMAP §2 estaba **71 atrás**: decía 175, eran 246.
#
# El segundo es el que justifica el script entero. Un número que nadie recalcula es un número
# que miente, y este era el de la "fuente de la verdad". Por eso abajo el conteo NO se escribe
# a mano: se mide y se compara contra lo que el ROADMAP declara.
#
# Sale con código != 0 si algo falla, así sirve de gate. Nada de acá necesita el robot.
set -uo pipefail   # NO -e: un chequeo que falla tiene que dejar correr a los demás

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

NET=0; GATE=0
for a in "$@"; do
  case "$a" in
    --net) NET=1 ;;
    --gate) GATE=1 ;;
    --all) NET=1; GATE=1 ;;
    -h|--help) sed -n '2,9p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "opción desconocida: $a (probá --help)" >&2; exit 2 ;;
  esac
done

FAILED=0
if [ -t 1 ]; then G=$'\e[32m'; R=$'\e[31m'; Y=$'\e[33m'; B=$'\e[1m'; N=$'\e[0m'
else G=""; R=""; Y=""; B=""; N=""; fi

section() { printf '\n%s== %s%s\n' "$B" "$1" "$N"; }
ok()   { printf '  %sOK%s   %s\n' "$G" "$N" "$1"; }
bad()  { printf '  %sFALLA%s %s\n' "$R" "$N" "$1"; FAILED=$((FAILED+1)); }
warn() { printf '  %saviso%s %s\n' "$Y" "$N" "$1"; }

# Los repos, en un solo lugar. Las tres listas NO son la misma a propósito: `unitree_ros2` se
# lintea entero pero sus tests viven en dos subdirectorios, y el frontend no tiene ruff.
LINT_PY=(AI-VL-ecosystem/AI-VL-core AI-VL-ecosystem/AI-VL-backend
         robot-ecosystem/robot-telemetry-agent robot-ecosystem/robot-command-relay
         robot-ecosystem/robot-video-pipeline unitree_ros2)
TESTS=(unitree_ros2/robot_executor unitree_ros2/robot_camera_bridge
       robot-ecosystem/robot-command-relay robot-ecosystem/robot-video-pipeline
       AI-VL-ecosystem/AI-VL-backend AI-VL-ecosystem/AI-VL-core)
GATE_REPOS=(AI-VL-ecosystem/AI-VL-core AI-VL-ecosystem/AI-VL-backend AI-VL-ecosystem/AI-VL-frontend
            unitree_ros2 robot-ecosystem/robot-telemetry-agent
            robot-ecosystem/robot-command-relay robot-ecosystem/robot-video-pipeline)

# Un repo con venv tiene que correr con ÉL. Los cuatro del robot no tienen y usan el python del
# sistema a propósito: el Jetson tampoco tiene venv, así que así se parece más al destino.
pyfor() { [ -x "$ROOT/$1/.venv/bin/python" ] && echo "$ROOT/$1/.venv/bin/python" || echo python3; }

# --------------------------------------------------------------------------- #
section "Herramientas"
# jscpd SIEMPRE como `bunx jscpd`: el shim global de bun ejecuta node, que no está instalado.
for t in ruff pre-commit pip-audit codebase-memory-mcp bun git docker; do
  v="$(command -v "$t" >/dev/null 2>&1 && "$t" --version 2>&1 | head -1)"
  [ -n "$v" ] && ok "$(printf '%-20s %s' "$t" "$v")" || bad "$(printf '%-20s no está en PATH' "$t")"
done
command -v node >/dev/null 2>&1 || warn "node no está instalado — el frontend corre con bun/bunx"

# --------------------------------------------------------------------------- #
section "Lint"
for r in "${LINT_PY[@]}"; do
  if out="$( (cd "$r" && ruff check --no-cache -q) 2>&1 )"; then ok "$(basename "$r")"
  else bad "$(basename "$r") — $(echo "$out" | tail -2 | tr '\n' ' ')"; fi
done
if out="$( (cd AI-VL-ecosystem/AI-VL-frontend && bunx eslint src && bun run typecheck) 2>&1 )"; then
  ok "AI-VL-frontend (eslint + tsc)"
else bad "AI-VL-frontend — $(echo "$out" | tail -3 | tr '\n' ' ')"; fi

# --------------------------------------------------------------------------- #
section "Tests — las seis suites"
TOTAL_PASS=0; TOTAL_XFAIL=0
for d in "${TESTS[@]}"; do
  line="$( (cd "$d" && "$(pyfor "$d")" -m pytest -q 2>&1 | tail -1) )"
  p="$(grep -oE '[0-9]+ passed' <<<"$line" | grep -oE '[0-9]+' || echo 0)"
  x="$(grep -oE '[0-9]+ xfailed' <<<"$line" | grep -oE '[0-9]+' || echo 0)"
  TOTAL_PASS=$((TOTAL_PASS + p)); TOTAL_XFAIL=$((TOTAL_XFAIL + x))
  # OJO con el patrón: `failed` a secas matchea DENTRO de `xfailed`, y un xfail es un defecto
  # registrado a propósito, no una falla. Hay que exigir el dígito y el espacio delante.
  if grep -qE '[0-9]+ (failed|error)' <<<"$line"; then bad "$(printf '%-42s %s' "$d" "$line")"
  else ok "$(printf '%-42s %s' "$d" "$line")"; fi
done
printf '\n  TOTAL medido: %s%s pasan, %s xfail%s\n' "$B" "$TOTAL_PASS" "$TOTAL_XFAIL" "$N"

# El número declarado vs el medido. Esta comparación ES el motivo del script: sin ella, el §2
# se desfasó 71 tests sin que nadie lo notara.
DECL="$(grep -oE '\*\*[0-9]+ pasan, [0-9]+ xfail' "$ROOT/.claude/ROADMAP.md" | head -1 | grep -oE '[0-9]+' | head -1)"
if [ -n "$DECL" ]; then
  if [ "$DECL" = "$TOTAL_PASS" ]; then ok "coincide con lo que declara ROADMAP.md §2 ($DECL)"
  else warn "ROADMAP.md §2 declara $DECL y hay $TOTAL_PASS — actualizá §2 (esto es lo que se desfasó antes)"; fi
else warn "no pude leer el conteo declarado en ROADMAP.md §2"; fi

# --------------------------------------------------------------------------- #
section "Grafo de codebase-memory"
if "$ROOT/.claude/hooks/reindex-if-needed.sh"; then ok "reindex corrió"
else bad "el hook de reindex falló"; fi
warn "frescura: NO la mide detect_changes (devuelve lo mismo antes y después de indexar)."
warn "          se verifica buscando un símbolo recién escrito con search_graph."

# --------------------------------------------------------------------------- #
if [ "$GATE" = 1 ]; then
section "Gate de pre-commit"
# `pre-commit run` a secas solo mira lo STAGED, y por eso el bloque original hacía `git add -A`
# (con --all-files se saltean los archivos sin trackear y da un falso OK en tests nuevos).
# Pero stagear siete repos desde un health check es un footgun: si después commiteás, te llevás
# todo puesto. Así que acá se toca el index SOLO si estaba vacío, y se deja como estaba.
#
# Y hay un segundo efecto que el `git reset` NO deshace: `trailing-whitespace` y
# `end-of-file-fixer` son hooks que REESCRIBEN el archivo. Por eso abajo se compara el árbol
# antes y después y se avisa por nombre de repo si el gate te tocó algo. Es la razón por la
# que `--gate` no viene por defecto.
treehash() { { git -C "$1" diff HEAD 2>/dev/null; git -C "$1" ls-files --others --exclude-standard 2>/dev/null; } | sha1sum; }
for r in "${GATE_REPOS[@]}"; do
  staged="$(git -C "$r" diff --cached --name-only 2>/dev/null | head -1)"
  if [ -n "$staged" ]; then warn "$(printf '%-24s tenés cosas staged, no toco tu index' "$(basename "$r")")"; continue; fi
  before="$(treehash "$r")"
  git -C "$r" add -A >/dev/null 2>&1
  if (cd "$r" && pre-commit run >/dev/null 2>&1); then ok "$(basename "$r")"; else bad "$(basename "$r")"; fi
  git -C "$r" reset -q >/dev/null 2>&1     # devolver el index a como estaba: vacío
  [ "$(treehash "$r")" != "$before" ] && warn "$(printf '%-24s el gate REESCRIBIÓ archivos acá (whitespace/EOF) — revisá el diff' "$(basename "$r")")"
done
fi

# --------------------------------------------------------------------------- #
if [ "$NET" = 1 ]; then
section "Servicios (informativo — no rompen el gate)"
hec="$(curl -sk --max-time 5 https://192.168.20.200:8088/services/collector/health 2>&1)"
grep -q healthy <<<"$hec" && ok "HEC de Splunk: $hec" || warn "HEC de Splunk sin responder: ${hec:-timeout}"
cam="$(curl -s --max-time 5 http://127.0.0.1:5000/api/stats 2>/dev/null \
      | python3 -c "import sys,json;d=json.load(sys.stdin)['cameras'];print('; '.join(f\"{k} fps={v.get('camera_fps')}\" for k,v in d.items()))" 2>/dev/null)"
if [ -n "$cam" ]; then
  grep -q 'fps=0' <<<"$cam" && warn "Frigate: $cam  ← fps 0 = el stream está caído" || ok "Frigate: $cam"
else warn "Frigate sin responder en :5000"; fi
fi

# --------------------------------------------------------------------------- #
printf '\n%s' "$B"
[ "$FAILED" = 0 ] && printf 'TODO VERDE%s\n' "$N" || printf '%s%s chequeo(s) en rojo%s\n' "$R" "$FAILED" "$N"
exit $(( FAILED > 0 ))
