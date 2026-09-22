# ROADMAP · Plataforma — Tracks C y D

> Parte del ROADMAP, partido el **2026-09-22**. La orientación —cómo leer, los dos robots, el
> estado real de cada capacidad, qué bloquea hoy y las decisiones abiertas— quedó en
> **`../ROADMAP.md`**, que es el archivo que se abre primero. Éste es **lo que no depende de ningún robot**: la app AI-VL, seguridad, tests, calidad y tooling.
>
> **La numeración de secciones NO cambió a propósito.** Una referencia `§5.2` escrita en
> cualquier doc o comentario del código sigue resolviendo; lo único que hay que saber es en
> qué archivo vive cada §, y eso está en la tabla de `../ROADMAP.md` §0.
>
> | § | Dónde |
> |---|---|
> | §0 §1 §2 §4 §9 | `../ROADMAP.md` — orientación |
> | §5 | `GO2.md` — Track A, el Go2 |
> | §6 | `G1.md` — Track B, el G1 |
> | §7 §8 | `PLATAFORMA.md` — app, seguridad, tests, tooling |
> | §3 §10 §11 | `BITACORA.md` — el registro con fecha |

---

## 7. Track C — App AI-VL y seguridad

### 7.1. P0 de seguridad — reverificados línea por línea el 2026-09-10

**Los cuatro de seguridad siguen abiertos.** Los **dos del `RelayTransport`** que salieron de
los xfails de §7.3 quedaron **arreglados el 2026-09-10**. Las referencias de línea de
`robot_executor_service.py` corrieron una posición desde el 28-08 y están corregidas acá; las
cuatro de `# noqa: S104` se verificaron exactas.

- [x] **`RelayTransport` inyectaba un halt en cada refresh** — hecho 2026-09-10. Posteaba
      `stop_move` incondicionalmente al salir del loop; ahora va detrás de
      `if reached_deadline` dentro de un `try/finally`, igual que Go2 (`:439`) y G1 (`:751`).
      **Confirmado contra el robot real antes de tocarlo**: 154 de 155 moves llevaban freno.
      Era la causa de los micro tirones (§2). Ver `FRENO-INYECTADO.md`.
- [x] **`RelayTransport` no clampeaba la duración** — hecho 2026-09-10. Se agregó el
      `max(0.1, min(step, MAX_STEP_S))` que ya estaba en `:449` y `:761`. `duration_s=60`
      dejó de ser una caminata de 60 s que el dead-man del robot no cortaba.
      Los dos xfails pasaron a `XPASS(strict)`, pytest falló, y los marcadores se borraron.
- [ ] **`SAFE_MODE` fail-safe.** `robot_executor_service.py:90` es
      `_as_bool(os.environ.get("SAFE_MODE"), False)` → **default permisivo**. Y `:1256`
      (`effective_safe = req_safe if isinstance(req_safe, bool) else SAFE_MODE`) deja que un
      request que omite el campo tome el camino permisivo. Poner `True` en los dos lados y
      alinear el docstring de `:16`, que **hoy afirma literalmente "`SAFE_MODE` (default on)"
      — un [blocker] de §1 del estándar, docs contra código**.
- [ ] **`continuous` fail-safe.** `go2_commands.py:127` y `g1_commands.py:279`:
      `bool(params.get("continuous", True))` → movimiento sin límite por default, desactivando
      el dead-man. Pasar a `False`; el xfail se da vuelta con eso.
- [ ] **Token en el borde de servicio.** El ejecutor y el camera bridge aceptan requests sin
      autenticar en `0.0.0.0`. Copiar el patrón Bearer del relay. Los 4 sitios están marcados
      con `# noqa: S104`: `robot_executor_service.py:84`, `robot_camera_bridge.py:58`,
      `relay_server.py:35`, `mjpeg_server.py:44`. Sacar el noqa a medida que se arreglan y
      ruff mantiene la regla.
- [ ] **Secuencia de comandos + barrera de `stop`.** Un `move` emitido antes de un `stop`
      puede aterrizar después. Necesita `seq` + `client_id` por las tres capas — por eso el
      contract test de §7.2 va primero.

### 7.2. Tests que no necesitan robot — hacer estos mientras el robot está apagado

- [x] **Contract test backend ↔ iacore** — hecho 2026-08-28.
      `AI-VL-backend/tests/test_iacore_contract.py` + su espejo
      `AI-VL-core/tests/test_backend_contract.py`. Congela los 4 modelos compartidos por
      **nombre de campo y orden** (los tipos y defaults difieren a propósito: el gateway no
      inventa valores, el servicio pone los de `config.json`). Lee las clases con `ast` en
      vez de importar — así no necesita FastAPI, pydantic, Ollama ni el repo hermano, y corre
      en CI donde solo hay un repo clonado. **Probado que muerde:** inyectando `seq` solo en
      iacore, los dos repos fallan. Cambiar un modelo es ahora un cambio de dos repos.
- [x] **Test del parser MJPEG** — hecho 2026-08-28. Los dos lados, uno por máquina:
      `robot-video-pipeline/tests/test_mjpeg_framing.py` (9 tests) y
      `unitree_ros2/robot_camera_bridge/tests/test_mjpeg_framing.py` (11 tests). Cubren frame
      partido entre chunks, marcador SOI y EOI a caballo de dos lecturas, preámbulo multipart,
      dos frames en un chunk, y frame truncado al cerrar. El bridge se testea sin cv2 ni
      rclpy (stubs en `conftest.py`), así que corre fuera del devcontainer.
      **El techo de buffer que falta quedó como `xfail(strict=True)` en los dos** — medido con
      `tracemalloc`: hoy el scanner retiene los 5 MB de un frame sin EOI.
- [ ] **Frontend: one-frame-in-flight** en el socket de detección — **pendiente, y necesita
      una decisión.** `vitest` corre en pre-commit y CI (`--passWithNoTests`), pero el repo
      **no tiene entorno DOM ni testing-library**, y el invariante vive dentro del closure de
      `useDetectionSocket`. Dos caminos: (a) agregar `jsdom` + `@testing-library/react` como
      devDeps — no van al bundle, pero cambian el lockfile y CI usa `--frozen-lockfile`;
      (b) extraer el predicado de gating a una función pura y testearla sin DOM — no agrega
      dependencias pero toca código del camino de video en vivo.

Los repos **sin suite** bajaron de cuatro a dos: quedan `AI-VL-core` (tiene el contract test,
pero nada de su inferencia) y `robot-telemetry-agent` (nada).

### 7.3. Los 6 xfails estrictos

Afirman el comportamiento **correcto** de defectos abiertos. `strict=True`: cuando arreglás el
defecto el test pasa inesperadamente y **pytest falla**, avisándote de borrar el marcador.
Arreglá el código, borrá el marcador — no borres el test.

Enumerados el 2026-09-10 corriendo `pytest -rxX` en los cuatro repos con suite. Eran **8** esa
mañana: la lista de antes omitía los dos del `RelayTransport`, que resultaron ser los más
graves de todos. **Esos dos se arreglaron el mismo día (§7.1) y sus marcadores ya no existen**,
así que quedan 6.

| Test | Repo | Defecto |
|---|---|---|
| `test_move_without_continuous_is_bounded` (×2 robots) | executor | `continuous` default `True` — P0 de §7.1 |
| `test_an_soi_with_no_eoi_does_not_grow_the_buffer_without_bound` (×2 copias) | camera_bridge, video-pipeline | el scanner MJPEG retiene los 5 MB de un frame sin EOI |
| `test_rate_limiter_does_not_allow_double_the_budget_across_a_boundary` | relay | ventanas fijas dejan pasar 2× en el borde |
| `test_token_comparison_is_constant_time` | relay | el relay compara el token con `==` |

> ✅ **`strict=True` se ganó el sueldo, y conviene entender cómo.** Los dos xfails del
> `RelayTransport` estaban escritos hacía días y **nadie los había leído**: no figuraban en
> ninguna lista de P0, así que el defecto más caro del sistema estaba documentado en rojo y
> sin priorizar. Al aplicar el arreglo pasaron a `XPASS(strict)` y pytest falló, que es
> justamente el aviso de borrar el marcador. **La lección: un xfail que no está registrado en
> este documento es un defecto que nadie va a priorizar.** Los dos tests quedaron
> parametrizados sobre los tres transportes, así que la divergencia no puede volver.

### 7.3.b. Cobertura de tests — el mapa de lo que no está protegido

`.claude/coverage.sh` (on demand, **no es un gate** — el porqué está en su cabecera). Medido
el 2026-08-28:

| Archivo | Stmts | Cobertura |
|---|---:|---:|
| `robot_executor_service.py` | 781 | **0%** |
| `AI-VL-core/menu.py` | 516 | 0% |
| `AI-VL-backend/app.py` | 454 | 0% |
| `src/vlm_common.py` | 290 | 0% |
| `robot_camera_bridge.py` | 196 | 0% |
| `service.py` (iacore) | 158 | 0% |
| `g1_fsm_watch.py` | 58 | 0% |
| `camera_sources.py` | 258 | 28% |
| `relay_server.py` | 171 | 31% |
| `mjpeg_server.py` | 202 | 36% |
| `g1_commands.py` | 130 | 77% |
| `go2_commands.py` | 49 | 84% |

`robot-telemetry-agent` no tiene suite: verde en CI porque no hay nada que correr.

**No poner umbral global.** Con 781 statements en 0%, un `fail under 80%` estilo JaCoCo
obligaría a escribir tests que ejecutan líneas sin afirmar nada — exactamente lo contrario de
la regla del estándar ("cada test nombra el defecto que atrapa"). Si algún día se quiere un
gate, la forma correcta acá es un **ratchet por archivo** (que `relay_server.py` no baje de
31%, que `go2_commands.py` no baje de 84%), no un número global.

Un ejemplo de coverage ganándose el sueldo: el bloque sin cubrir 273-298 de `relay_server.py`
contiene el comentario *"Closing the child's stdin makes command_sender StopMove before it
exits, so shutting the relay down can never leave the robot walking"*. Es una **garantía de
seguridad documentada que ningún test ejercita**.

### 7.4. Calidad y duplicación (medido)

- [ ] **Helper de proxy en el gateway** — 9 `httpx.AsyncClient` por request en
      `app.py:227-396`, en bloques try/except casi idénticos. Un helper y dos clientes
      persistentes en el `lifespan`. Es también donde caen los headers de auth, una sola vez.
- [ ] **Template method para el dead-man** — implementado tres veces en
      `robot_executor_service.py`, 70% idéntico entre los dos transportes ROS2. La clase base
      se queda con el loop, el deadline, el lock y el thread; cada transporte implementa solo
      `_publish_velocity()` y `_publish_stop()`.
      `bunx jscpd unitree_ros2/robot_executor --min-lines 12 --min-tokens 60` → 3 clones, 45 líneas.

      > 🔎 **Reclasificado el 2026-08-28: ya no necesita el robot.** Estaba diferido porque
      > refactorizar el mecanismo que frena al robot sin poder probarlo era inaceptable, y
      > coverage confirmó que el archivo está en **0%** — cero red de seguridad. Pero el
      > spike mostró que la barrera no es técnica: `robot_executor_service.py` **se importa
      > limpio en 0,03 s sin un solo stub** (`rclpy` se importa lazy, dentro de funciones en
      > `:125`, `:286` y `:310`, no a nivel módulo) y **no arranca ningún thread** al
      > importarse (`serve_forever` está en `main()`, detrás de `if __name__`). Además ya
      > existe la base `RobotTransport(ABC)` en `:329` con 4 subclases.
      > **Orden correcto:** primero tests del dead-man con reloj falso (sin robot, sin DDS),
      > y con esos tests verdes recién el refactor. Nadie lo intentó — el 0% no era un
      > impedimento, era un descuido.
- [ ] **Helpers compartidos en el fork** — `_load_dotenv` y `_as_bool` copiados entre el
      ejecutor y el camera bridge; `_clamp` byte-idéntico en los dos módulos de comandos.
      Mismo repo, un `common.py` no rompe ningún borde.
- [x] **5 hooks de fetch-on-mount sin `AbortController`** — hecho 2026-08-28. `useSpeech`,
      `useOptions`, `usePresence`, `CameraControls`, `NetworkControls`. Para eso hubo que
      agregar `signal?: AbortSignal` opcional a 6 GET de `api/backend.ts`, siguiendo el patrón
      que `askVlm`/`interpretCommand` ya usaban; es aditivo, ningún call site existente cambió.
      Dos casos valían más que el warning de React: en `useSpeech`, un abort caía en el
      `.catch` y ponía la lista de voces en vacío — o sea "el server no tiene voces neurales",
      degradando al TTS del browser en silencio; en `NetworkControls`, una respuesta lenta del
      robot ANTERIOR podía aterrizar después de cambiar de robot y repintar los campos con el
      transporte equivocado.
      **Nota, fuera de alcance:** los `setTimeout(loadStatus, …)` de `NetworkControls`
      (líneas 93 y 111-114) tampoco se limpian al desmontar. Es previo, no lo toqué.

### 7.5. Producto / UX — de `FIX.txt`

Lo que estaba en `FIX.txt` como notas crudas, ordenado. `FIX.txt` sigue existiendo como
libreta de ideas; lo que se decide hacer sube acá.

- [ ] **`"caminá un segundo"` sigue caminando indefinidamente.** Es el mismo bug que el P0 de
      `continuous` en §7.1 — se arregla ahí, no en el front.
- [ ] **La app se fija en `192.168.123.161` al iniciar**, que es el bajo nivel de *los dos*
      robots. Está en `robot_executor_service.py:87` como `ROBOT_IP`, comentado
      *"informational (health/ping)"*. Diagnosticado: el health check apunta al bajo nivel;
      debería usar el alto nivel del robot seleccionado.
- [ ] **`SAFE_MODE` off tiene que verse en rojo**, y con safe on los botones peligrosos van
      `disabled`.
- [ ] **Selección de robot global desde el header**, con los botones cambiando según el robot.
- [ ] **Pill de estado que diga la verdad** — hoy dice "connected" cuando lo único que pasa es
      que se está mostrando la cámara.
- [ ] Lista de acciones disponibles en el front, tocables directo, dependiente del robot.
- [ ] Control tipo joystick.
- [ ] **Persistencia** (fase 3 de `ARCHITECTURE.md` §10, nunca construida): Redis para
      telemetría caliente y pub/sub, Mongo para detecciones/chat/eventos, frames a FS/MinIO
      con referencias. Es lo mismo que *"poner una base de datos para que la ia tenga más
      contexto"* de `FIX.txt`.
- [ ] Micrófono y parlantes del robot — cubrir lo que hace la app oficial de Unitree.
- [ ] Mejorar el TTS.
- [ ] Examples en español en `command_common.py` (hoy el matching de skill falla seguido).
- [ ] Batería expuesta; resolución y fps del video configurables.
- [ ] Reestructurar la vista de VLM (no se entiende).
- [ ] Arreglar el modo view-only.

### 7.6. Housekeeping

- [x] Borrar `unitree_ros2/setupOLD.sh` y
      `robot-video-pipeline/frigate/config/backup_config.yaml` — hecho 2026-08-28.
      Verificado antes: cero referencias en código, scripts, unidades systemd y configs.
      `setupOLD.sh` estaba trackeado (recuperable con `git checkout`). `backup_config.yaml`
      **no** estaba trackeado — lo gitignorea `/frigate/config/*` — así que se movió aparte en
      vez de borrarse: era una copia de `config.yml` de antes de la mudanza de IP, su única
      diferencia real era el `192.168.123.99` viejo. Frigate siguió healthy después.
- [ ] Destrackear `unitree_ros2/dds.env` — se escribe en runtime por `POST /dds`, así que cada
      cambio de red desde la UI ensucia el repo.
- [ ] Traducir **2** strings en español del frontend — **[blocker]** por la regla de idioma.
      *(Corregido 2026-08-28: `STATE.md` decía "4 strings en `ControlPage.tsx:280-312`".
      `ControlPage.tsx` no tiene **ni un** carácter acentuado en sus 502 líneas; el dato estaba
      mal. Ubicación real:)*
      - `components/live/CommandPanel.tsx:239` — `Auto ON — se ejecuta solo al interpretar (sin botón)`
      - `hooks/useGamepad.ts:174` — `"despues tocá un boton del joystick (…)"`

      **NO tocar** los otros dos hits de castellano, que son correctos a propósito:
      `CommandPanel.tsx:105` y `:116` traen *ejemplos* de comandos en español
      (`"andá para adelante"`, `"levantá las manos"`) dentro de texto en inglés — el usuario le
      habla al robot en español, así que los ejemplos tienen que estar en español.
- [ ] Anotar en `robot-video-pipeline/README.md` que `go2_h264_stream.cpp` se compila pero no
      está en ningún camino de runtime. **Ojo:** eso solo si se descarta el experimento de
      §5.2 (`rt/frontvideostream` local), que es justamente retomar ese archivo. Decidir una
      cosa o la otra, no las dos.
- [ ] Decidir qué hacer con `AI-VL-ecosystem/.mcp.json` y su hook en `settings.local.json`:
      inofensivo mientras las sesiones se abran desde `~/Desktop`, pero abrir desde ese
      directorio carga una config que indexa 4 de 11 repos.
- [ ] **Terminar la convención de ramas del 10-09** (tabla completa en §0). Tres cosas:
      renombrar `master` → `main` en `robot-command-relay` desde GitHub; mergear a la
      principal `robot-ecosystem` y `robot-splunk-docs`, que siguen en `dev`; y decidir qué
      pasa con `unitree_ros2`, que está en `feature/dev2` **y tiene código que corre en el
      robot**. Mientras tanto ningún `for` sobre los repos puede asumir una rama.
- [ ] **`AI-VL-frontend` está en la rama `feature/both-robots-same-tiem`** mientras sus tres
      hermanos están en `...same-time`. Verificado el 2026-09-10, sigue así. Va a molestar
      cuando los PR suban juntos.
- [ ] **Cerrar `ARQUITECTURA_ROBOT_G1_PROPUESTA.md`**, que la cabecera del ROADMAP daba
      por borrado desde el 28-08 y sigue trackeado (ver el aviso al principio de `../ROADMAP.md`). Antes de
      borrarlo hay que sacar las dos referencias vivas: `AI-VL-ecosystem/ROBOT_CONTROL.md` y
      `docs/G1_FASES_Y_CREAR_SKILLS.md`. Si algo suyo todavía vale, sube a §6; si no, se borra
      y git lo recuerda.
- [ ] Sacar las 14 menciones de `192.168.123.99` de los docs (§3).

---
## 8. Track D — plataforma

Todo esto está en pie y verificado; es mantenimiento, no construcción.

- **Estándar**: `.claude/skills/cr/references/standard.md`, 10 secciones, cada regla con su
  incidente. La review corre con `/cr` sobre los 11 repos.
- **Lint**: `ruff.toml` por repo. Los tres repos del robot fijan `target-version = "py38"` y
  habilitan `FA`, así el linter rechaza sintaxis 3.9+ que el Jetson no puede correr.
- **Commit gate**: `pre-commit` en los 7 repos con código. El formateo **no** se fuerza a
  propósito (standard §9 explica por qué).
- **CI**: 7/7 verdes, los repos del robot sobre `ubuntu-22.04` con **Python 3.8**. Ya se ganó
  el sueldo: agarró un `set[str]` que pasa en 3.14 y explota en 3.8.
- **Grafo**: 12 proyectos indexados, UI en `http://127.0.0.1:9749`. Desde el **2026-09-22** el
  refresco es por **`PostToolUse`** además de session start/stop: el grafo queda al día en la
  misma edición, no un turno después (0,165 s, asíncrono). Ese mismo día se arregló un defecto
  del hook que lo hacía ver **solo el primer cambio de cada archivo** — la firma era
  `sha1(git status --porcelain)`, que es idéntica para "modificado" y "modificado otra vez";
  ahora sigue contenido (`git diff HEAD` + los untracked). Dos advertencias sobre el grafo, las
  dos medidas ese día, están en el `CLAUDE.md` del workspace: `detect_changes` **no** sirve
  para saber si el índice está viejo, y el servidor MCP puede responder desde una vista más
  vieja que el store.

### Health check

```bash
cd ~/Desktop

# Herramientas (jscpd SIEMPRE como `bunx jscpd`: el shim global de bun ejecuta node, que no está)
for t in ruff pre-commit pip-audit codebase-memory-mcp bun; do printf '%-22s %s\n' "$t" "$($t --version 2>&1|head -1)"; done
AI-VL-ecosystem/AI-VL-core/.venv/bin/pytest --version
(cd AI-VL-ecosystem/AI-VL-frontend && bunx eslint --version && bunx vitest --version)

# Lint: los seis repos Python y el frontend tienen que dar limpio
for r in AI-VL-ecosystem/AI-VL-core AI-VL-ecosystem/AI-VL-backend \
         robot-ecosystem/robot-telemetry-agent robot-ecosystem/robot-command-relay \
         robot-ecosystem/robot-video-pipeline unitree_ros2; do
  printf '%-24s ' "$(basename $r)"; (cd $r && ruff check --no-cache -q && echo OK)
done
(cd AI-VL-ecosystem/AI-VL-frontend && bunx eslint src && bun run typecheck)

# Tests: las SEIS suites, 105 passed + 8 xfailed en total (2026-09-10). Antes esto corría
# solo dos de las seis, así que el número de §2 no se podía verificar con el health check.
for d in unitree_ros2/robot_executor unitree_ros2/robot_camera_bridge \
         robot-ecosystem/robot-command-relay robot-ecosystem/robot-video-pipeline \
         AI-VL-ecosystem/AI-VL-backend AI-VL-ecosystem/AI-VL-core; do
  printf '%-42s ' "$d"; (cd $d && python3 -m pytest -q 2>&1 | tail -1)
done
# Y los 8 xfail con su motivo, que es donde viven los defectos abiertos (§7.3):
(cd unitree_ros2/robot_executor && python3 -m pytest -q -rxX | /usr/bin/grep '^XFAIL')

# El gate de commit, exactamente como lo invoca git (NO --all-files: eso saltea los archivos
# sin trackear y da un falso OK en tests nuevos)
for r in AI-VL-ecosystem/AI-VL-{core,backend,frontend} unitree_ros2 \
         robot-ecosystem/robot-{telemetry-agent,command-relay,video-pipeline}; do
  (cd $r && git add -A && pre-commit run >/dev/null 2>&1; printf '%-24s rc=%s\n' "$(basename $r)" $?)
done

# El grafo
.claude/hooks/reindex-if-needed.sh && echo "reindex OK"

# El HEC de Splunk
curl -sk --max-time 5 https://192.168.20.200:8088/services/collector/health

# Frigate: si camera_fps es 0, el stream está caído
curl -s --max-time 5 http://127.0.0.1:5000/api/stats | python3 -c "import sys,json;print(json.load(sys.stdin)['cameras'])"
```

Dos cosas que esto **no** puede chequear, porque se cargan al arrancar la sesión: que `/mcp`
muestre `codebase-memory-mcp` **connected**, y que el hook de reindex dispare al inicio (si no,
abrir `/hooks` una vez recarga la config).

---
