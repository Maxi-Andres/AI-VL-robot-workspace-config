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


> ⚠️ **2026-10-07 — el G1 apuntaba al relay del Go2.** `G1_RELAY_URL` (y por lo tanto el ping)
> quedó en `http://10.1.254.18:8092`: el header mostraba los dos robots "online" y un comando
> para el G1 lo habría ejecutado el perro. Causa: *Connection* en la página Robot mantenía los
> campos del robot anterior si la recarga no llegaba, y la URL se guarda al perder el foco.
> Arreglado en tres capas: config corregida (`192.168.51.115:8092`); la página bloquea los
> campos hasta cargar los del robot elegido y sólo guarda valores cambiados; y el executor
> **rechaza** un comando si el `robot_model` que reporta el relay no es el del robot
> (`tests/test_relay_identity.py`).

## 7. Track C — App AI-VL y seguridad

### 7.1. P0 de seguridad — reverificados línea por línea el 2026-09-10

> **Usuario 2026-10-28:** la capa de comandos "va a volar" (se reemplaza), así que estos no se
> hacen ahora; `SAFE_MODE` "ya está bien" (lo fija el entorno; el default del código sigue en
> `False`, `robot_executor_service.py:113`, verificado ese día).

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

- [x] **Helper de proxy en el gateway — HECHO 2026-10-29 (ffaa3d7).** El cliente a iacore ya era
      uno solo (lifespan); los 9 bloques al executor y al camera bridge pasaron a `downstream()`.
      Lo de abajo es el texto original: 9 `httpx.AsyncClient` por request en
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

- [ ] **Pasada completa de UI y UX de la app** — **el rework de la maqueta B + C YA ENTRÓ al repo
      (verificado 2026-10-29):** Fleet como inicio, Settings junta Robot + Video + Team, Live con
      pestañas Ask VLM / Detection / Command (experimental), Drive estilo cockpit con pantalla
      completa, Joints, Memory, idioma inglés/español, SSO. Lo que sigue abierto ya no es el
      overhaul sino una revisión del front nuevo (ver la respuesta de esa fecha). **Responsive
      HECHO 2026-10-29** (frontend e658915, 7160dd6): medido con Playwright en 390/820/1180 px,
      claro y oscuro, 51/51 sin desborde, y las 6 pestañas visibles de 390 a 1920 px (antes se
      escondían en todo ancho < 1440). Header en dos filas debajo de 1280 (ícono sobre palabra
      en el teléfono); menús del header a todo el ancho del teléfono; Settings con fila de
      secciones fija. Script: `responsive.py` (scratchpad, contra un backend de prueba). Texto original:
      (pedido 2026-10-20, repetido 2026-10-22: "un
      overhaul de todo el front"; para después). **La app se llama Silk Pilot** desde 2026-10-22
      (frontend `c8233aa`: título "Silk Pilot", header = logo de Silk + "Pilot"). No un arreglo
      puntual: revisar las cinco pestañas (Live, Drive, Robot, Video, Joints) como un todo —
      jerarquía visual, densidad del header, consistencia de controles y estados, flujos que no
      se entienden. Absorbe a los ítems sueltos de UX de esta lista (vista de VLM, pill de
      estado, SAFE_MODE en rojo, selección de robot global). Ya hecho como punto de partida:
      logo de Silk en el header (frontend `6ab8ba2`, `2e35f21`). **2026-10-26: tres maquetas
      HTML** (solo maqueta, fuera del repo) en `~/Documents/silk-pilot-mockups/index.html` —
      A Mission Control (oscura, sidebar con flota), B Clarity (clara, flota primero), C Cockpit
      (video a pantalla completa, Ctrl K); colores de marca del logo, teal `#54bbb0` → amarillo
      `#e2d84a`. **Elegida B + la pantalla completa de C**; segunda vuelta en `pilot.html` (misma
      carpeta): login con cuentas y equipo/roles, Fleet con saludo, Drive (= "Live console") sin
      scroll de página y con el panel de acciones con scroll propio, pantalla completa estilo C,
      Live como la actual pero ordenada (pestañas Ask VLM / Detection / Command, el intérprete
      marcado como experimental), Joints (el dibujo es placeholder: va el modelo 3D actual), y
      Settings que junta Robot + Video. La maqueta no incluye Agent porque todavía no existe.
      **Dicho por el usuario 2026-10-26, para cuando se haga:** Agent es una pestaña nueva propia
      (`G1-GROOT.md` paso 6) y, cuando llegue, el Command (intérprete de un solo skill) **se va
      de Live**. Hasta entonces, Live queda como hoy, Command incluido. Falta: el visto bueno del
      usuario y sus referencias antes de pasarlo al repo. Pendiente parecido en Splunk:
      un ícono de carga más visual que el texto "cargando" (`GO2.md` §5.6).
- [ ] **Usuarios, roles y login — de verdad** (pedido 2026-10-26: "esto se vende en serio";
      decisiones en `ROADMAP.md` §9). Va en fases, una por vez para que el usuario la revise.
      Roles por organización: viewer (mira) < operator (+ IA, manejar, acciones, Joints) <
      admin (+ config de robot y video, personas) < owner (+ la organización).
  - [x] **Fase 1 — base + login + primer arranque** (hecha y aprobada 2026-10-26: backend
        `1805d0f`, frontend `53a7a4b`, unitree_ros2 `930da23`, ecosystem `cdee050`; el panel de
        marca quedó sin los cuadros flotantes, a pedido). Backend: `auth.py` + `db.py` + `migrations/` + `pilot_admin.py`;
        **todas** las rutas y WebSockets del gateway piden sesión o device key, con tabla
        `POLICY` por ruta y default deny (`tests/test_auth.py` falla si una ruta no tiene
        entrada) — cierra el "gateway sin credencial" del estándar §2. Sesión: token opaco,
        cookie httpOnly + SameSite=Strict, en la base solo el SHA-256; 12 h, o 30 días con
        "keep me signed in", tope 90; cerrar sesión cierra también los WebSockets abiertos.
        argon2id, throttle 5 fallos/15 min por cuenta, mismo mensaje y mismo tiempo para mail
        inexistente. Primer arranque con código de un solo uso en `~/.pilot/setup-code` (0600),
        para que nadie en la red se adueñe de una instalación nueva. Auditoría de login, setup
        y cambios de config. El **camera bridge** usa una device key que el backend crea solo
        (`~/.pilot/device-key`) y `run-with-robot.sh` le pasa al contenedor. Front: `AuthGate`,
        login y asistente de 3 pasos con el estilo de la maqueta B (`.theme-light`, Manrope
        empaquetada), menú de usuario en el header; todo pasa por `backendFetch` y un 401 vuelve
        al login. Tests: backend 51, front 75, bridge 98. **Al reiniciar `run.sh` por primera
        vez pide el setup: `cat ~/.pilot/setup-code`.**
  - [x] **Fase 2 — invitaciones y Team & roles** (hecha y aprobada 2026-10-26: backend `7fa410b`, frontend `b20d903`). Backend `team.py` + migración `0002_invitations`: invitar con
        rol (enlace `/invite#token=…` de 7 días, un solo uso, token en el fragmento para que no
        quede en ningún log; se copia, SMTP después), aceptar eligiendo nombre y contraseña,
        cambiar rol y deshabilitar (cierra todas sus sesiones al instante, WebSockets
        incluidos). Reglas de rango: nadie da un rol mayor al suyo, toca a alguien de mayor
        rango ni se cambia a sí mismo; la empresa nunca queda sin owner activo. `operate` se
        audita como mucho una vez por minuto por sesión y ruta, en segundo plano. Arreglado de
        paso: un viewer podía cambiar la config compartida de YOLO por `/ws/view`; ahora pide
        `analyze`. `pilot_admin.py device-key create … --role viewer` para scripts de solo
        lectura. Front: página Team (solo tokens del tema, sirve en oscuro y en claro), diálogo
        de invitación con qué puede cada rol, pantalla para aceptar la invitación, y la UI
        oculta lo que el rol no puede (nav, paneles de Live, "Take control" en Joints, rutas
        protegidas con "Not available for your role"). Tests: backend 56, front 75; flujo
        completo probado en navegador.
  - [x] **Contraseña olvidada** (pregunta del usuario 2026-10-26: "¿y si se olvida el admin?").
        **Hecho 2026-10-26:** Team → "Reset password" genera un enlace `/reset-password#token=…`
        de un solo uso y 24 h (migración `0003_password_resets`); al usarlo cierra todas las
        demás sesiones de esa persona. Break-glass del único owner documentado en el README del
        backend.
        Propuesta: botón "Reset password" en Team que genera un enlace de un solo uso (como la
        invitación) para que un admin se lo pase a la persona; si se olvida el **único** owner,
        la salida es en el servidor (`pilot_admin.py set-password`, en el producto
        `silk-pilot reset-password`): mismo nivel de confianza que el código de setup; con SMTP
        (fase 4) se suma el "olvidé mi contraseña" por mail para todos. **Hecho 2026-10-26:** el
        aviso en Team cuando hay un solo owner, y que el reset desde el servidor deje fila de
        auditoría. El usuario eligió para el login el subtítulo "Live video, AI perception and
        safe teleoperation for robots — on your own server." (título sin cambios).
  - [x] **Fase 3 — sitios, mapa y robots** (hecha 2026-10-26: backend `01e4da4`, frontend `6bb447e`). Backend `fleet.py` + migración
        `0004_sites_robots`: sitios (nombre, zona horaria, dirección, ubicación, plano) y robots
        (nombre, número de serie, sitio). Cada robot ocupa un **slot** del stack (`go2`/`g1`):
        el executor, el relay y el bridge conocen un robot por modelo, así que hoy hay uno por
        slot por empresa (depende de la decisión abierta "cómo separar los dos robots"). El
        plano se sube como cuerpo crudo, se valida por sus bytes (PNG/JPEG/WebP), máx. 10 MB,
        en `~/.pilot/site-plans/`. **Mapa:** ubicación con Leaflet + OpenStreetMap; el satelital
        gratis de Esri **no** tiene licencia para un producto, así que no hay capa satelital (si
        un cliente la pide: proveedor con key). `tzdata` en Python para los alias de zona que
        reportan los navegadores. Front: página **Fleet** (saludo, checklist de arranque para
        admins — sitio, robots, equipo —, un bloque por sitio con plano o mapa, hora local y
        los robots con su estado real: el mismo ping y batería de las pills; botones Live/Drive
        que eligen ese robot). Tests: backend 61.
  - [x] **Fleet es la pantalla de inicio y la app pasa al diseño nuevo** (pedido 2026-10-26:
        "que sea la pantalla de inicio, hacé el front lindo como el de ejemplo"). Fleet en `/`,
        Live en `/live`. **Temas claro (default) y oscuro** con selector Light/Dark/System en el
        menú de usuario; todos los colores pasaron a tokens del tema (no más hex sueltos), así
        que **todas** las pantallas cambian de tema. Header nuevo como la maqueta (logo, empresa,
        pestañas con íconos, chip del robot con estado y batería que despliega los indicadores
        y el selector de robot, con los nombres registrados en Fleet). Fleet con el diseño de la
        maqueta B: KPIs reales (robots online, sitios, equipo, video en vivo), tarjetas de robot
        con la **imagen en vivo** de su cámara cuando es el que transmite, mapa/plano del sitio
        con selector de sitio, y feed de **actividad** (`GET /api/activity`, solo admins: sale
        de la auditoría). **Drive migrado** (2026-10-26): sin scroll de página, panel con
        pestañas Actions/Speak/Log y scroll propio (buscador, grupos plegables, candado en lo que
        bloquea Safe o el relay), teclas que se iluminan, STOP grande, y pantalla completa tipo
        cockpit (joysticks, cinta de velocidad y STOP, cajón de acciones). Solo presentación: la
        lógica de armado, dead-man y paradas no cambió. **Live migrado** (2026-10-26): video a
        todo lo alto con controles encima (fuente, chip de YOLO con conteo, barra de cámara
        propia), lecturas abajo (fps, inferencia, objetos, chips por clase), y panel con
        pestañas Ask VLM / Detection / Command (este último marcado experimental, como estaba
        pedido); botones de toda la app con el estilo nuevo. **Joints migrado** (2026-10-26):
        fuente arriba, escenario 3D que sigue el tema (canvas transparente + degradé, grilla que
        se redibuja al cambiar de tema), panel con pestañas Control / Joint / Health / All joints
        (Joint se abre solo al tocar una pieza, salvo con los brazos tomados). **Settings**
        (2026-10-26): Robot + Video en una sola página `/settings` con menú lateral (robot que
        se configura, secciones que siguen el scroll) y barra fija de Apply; `/robot` y
        `/video` redirigen. **Con esto todas las pantallas están en el diseño nuevo.**
  - [ ] **Siguiente en Fleet** (propuestas, sin pedir): robots ubicados sobre el plano (GPS
        del Go2 afuera; adentro hace falta localización). **Hecho:** el selector del header
        muestra los nombres registrados; **buscar la dirección en el mapa** (2026-10-26,
        Nominatim de OpenStreetMap, uso liviano, desde el navegador: Enter o la lupa, un
        resultado se aplica solo, varios se listan); panel **System** al lado de la actividad
        (motor de IA, control del robot, video, sesión en vivo — todo de `/api/presence`, sin
        backend nuevo) y tile "Add a robot" para que una flota corta llene su fila.
        **Satelital construido** (2026-10-26): Esri World Imagery, por defecto cuando el
        servidor tiene key (`ESRI_API_KEY` o `~/.pilot/esri-api-key`, sin reiniciar), botón
        Satellite/Map en el mapa; sin key queda solo el callejero. El crédito de los tiles se
        pliega en una (i) a los 5 s (lo exige la licencia, no se puede sacar). El header de
        Fleet: Invite + **Go live** en una tarjeta (el "Add robot" quedó solo en el tile).
        **Falta del usuario:** crear la cuenta gratuita de ArcGIS Location Platform y una API
        key limitada a basemaps; decidir si la key es de Silk (una para todos) o de cada
        cliente. "New mission" del maquetado espera a que existan misiones.
  - [x] **Header, Settings y estado de robots como el maquetado** (2026-10-26): header de 64 px
        con la medida del maquetado, barra de pestaña de 3 px que se desliza; menús (vos,
        servicios, robot) con la animación del maquetado (`DropMenu`); pill "N of M services"
        (de `/api/presence`, misma fuente que el panel System de Fleet). **Team se fue a
        Settings**: Account = Profile (nombre, apariencia, cambiar contraseña: cierra las demás
        sesiones; `PATCH /api/auth/me`, `POST /api/auth/password`) + Team & roles + Activity
        (todo el registro, de a 30, "View all" desde Fleet). Settings abierto a todos; Robot y
        Video solo con `configure`. Un color por persona (hash del id). **Estado guardado de
        cada robot** (`robot_watch.py`, cada 15 s aunque nadie mire): online desde, visto por
        última vez, latencia (RTT del ping), enlace, última batería; cambia de estado recién con
        2 muestras iguales y lo anota en Activity. Tarjetas: "Offline · 2 h", batería vieja en
        gris, foto en gris si está offline.
        **2026-10-27:** una sola pill de robots + servicios (elige el robot activo y conserva
        su nombre: nunca manejar uno creyendo que es el otro), **buscador** (Ctrl+K: páginas,
        robots, sitios, gente, secciones de Settings), **campana** (`/api/notifications`: lo de
        los robots para todos, lo demás solo con `configure`; nunca lo propio; no-leídas por
        persona con `users.notifications_seen_at`). **Colores al azar** por persona y por robot
        (`db.COLORS`, migración 0006 pintó los existentes), cambiables en Profile y en el
        diálogo del robot. **Activity paginada de verdad** (total contado en el server, páginas
        numeradas, filtros Robots/Sites/People/Access, índice `org_id+at`). **Team online**
        (`/api/team/online`: sesión con pedido en los últimos 3 min) en vez de "activos".
        **Del maquetado falta:** "Driving/Watching" por robot, misiones, KPIs de latencia de
        video y datos celulares, Grid/Table, robots sobre el mapa del sitio.
  - [x] **Live: asistente de visión como chat** (2026-10-27): conversación arriba, caja abajo;
        "Find objects" (el escaneo estructurado: su JSON es para un programa — la IA del robot
        algún día —, la persona lo ve como lista + cajas azules, el JSON plegado) separado de
        las preguntas. **Conversaciones guardadas por persona** (`chats.py`, migración 0007:
        privadas, ni un owner ve las de otro; cambiar, nueva, borrar; sobreviven cambio de
        cámara, recarga y otra compu). **Voz:** manos libres sin palabra clave ("Just speak":
        el nivel del mic detecta la frase, Whisper en el server, se manda solo; no escucha
        mientras habla la respuesta ni su eco — anda en Brave, que no tiene Web Speech), botón
        de mic para una pregunta, "Say robot" queda como opción; volumen del dispositivo o del
        parlante del robot (`useRobotVolume`, compartido con Drive). Live abre en la cámara del
        robot (la webcam propia es una elección). Probado con una pregunta hablada real.
  - [x] **Preferencias por persona y backup diario** (2026-10-27): `users.preferences`
        (migración 0009; `GET/PATCH /api/auth/preferences`, lista cerrada `auth.PREFERENCES`):
        tema, volumen, voz, hablar, muletilla, manos libres y su modo, salida, mapa, última
        conversación siguen a la persona; lo de UNA consola queda en el navegador (Robot armado,
        robot activo, mic del robot). Al entrar se cargan antes de mostrar la app; la primera
        vez se sube lo que el navegador tenía, salvo que fuera de otra persona. `backup.py`:
        carpeta fechada con `pilot.db` (API de backup de SQLite) + el resto de `~/.pilot`, al
        arrancar y cada 24 h, quedan 7 (`PILOT_BACKUP_DIR/KEEP/HOURS`); Settings → Backups
        (owner) con "Back up now". **Falta:** que el destino sea otro disco
        (`PILOT_BACKUP_DIR`) en cada instalación; restaurar es manual. También: links de
        invitación sobre la dirección de la empresa (`organizations.public_url`, nunca
        localhost), barra de guardado de Video solo con cambios, chips del video según tema.
  - [x] **Idiomas: inglés y español** (2026-10-27): todo texto visible por `t()` (clave = el
        inglés), español por área en `src/i18n/es/*.ts`, test que falla si falta una traducción,
        se pierde un placeholder o una clave queda en dos archivos; selector en el menú, Profile
        y el login; idioma guardado en el perfil; mensajes del servidor traducidos por
        coincidencia exacta (los armados con datos quedan en inglés). Español neutro con "tú".
        No se traduce: datos del servidor/robot (nombres de acciones del catálogo, nombres de
        robots), nombres de producto/protocolo, lo que dice la voz. Selectores segmentados con
        pastilla deslizante en toda la app. Pantalla completa del video = expandir dentro de la
        página (la Fullscreen API congelaba todo Firefox acá).
  - [ ] **Rehacer Settings antes de vender — anotado 2026-10-27, no ahora.** El usuario: "hay
        muchas cosas y está raro". Hoy mezcla en una sola página cosas de un usuario (Account,
        apariencia, idioma), de la empresa (Team, Organization, Backups) y técnicas del robot y
        del video (conexión DDS, transporte, cámara, calidad, YOLO). Para un producto que se
        vende hay que separar quién ve qué y en qué lenguaje: la persona, el admin de la
        empresa, y lo técnico (que el cliente casi nunca toca, o que va detrás de "Avanzado").
        Revisar también qué de Robot/Video sobra una vez que exista el instalador (§ Producto).
  - [ ] **Misiones en Fleet** (anotado 2026-10-27): la cuarta tarjeta de arriba de Fleet era
        "Live video: Off" y no tenía sentido; ahora es "Services up". Cuando existan las
        misiones, ese lugar es para ellas (y el "New mission" del maquetado).
  - [x] **SSO por OIDC — construido 2026-10-27** (`sso.py`, migración 0010, Settings → Single
        sign-on): Microsoft Entra, Google u otro OIDC; código + PKCE, state en cookie Lax y por el
        proveedor, firma del id_token contra las claves publicadas. Decidido con el usuario: OIDC
        (no SAML como Splunk), **entran solo los invitados** (cuenta ya vinculada → mail →
        invitación pendiente), la **contraseña queda** como entrada de emergencia. Tenant
        `common` rechazado. Probado con un proveedor falso que firma RS256 (12 tests + Firefox de
        punta a punta), **no con Entra real**. **Falta para usarlo de verdad:**
        1. Registrar la app en Entra (alguien con permiso de admin del tenant; Splunk ya tiene una
           registrada, la misma persona sabe hacerlo): redirect URI Web, client ID, tenant, secreto.
        2. **Un nombre para Pilot**: Entra acepta https en cualquier lado y http solo en localhost.
           Hoy se entra por `https://<ip>:8443` con certificado propio. El mismo esquema que Splunk
           (medido 2026-10-27): DNS de silk-technologies.com en **GoDaddy** (`ns63/64.domaincontrol.com`;
           el usuario no recuerda la cuenta — la tiene quien creó `splunk.` el 26/10), registro A
           `splunk` → **201.216.197.132** (nginx de la oficina), certificado **Let's Encrypt**
           (emitido 26/10 22:50, renueva certbot). Para Pilot: registro A `pilot` → la misma IP, un
           `server` en ese nginx hacia `https://192.168.20.99:8443` **con Upgrade/Connection para
           los WebSockets** (video, detección, joints), `certbot --nginx -d pilot.silk-technologies.com`,
           y Pilot con esa dirección como pública (Team, al invitar).
        **2026-10-27, decidido: se publica a internet** (el jefe lo quiere así). Hecho ese día:
        registro A `pilot` → 201.216.197.132 creado en GoDaddy; guía completa del nginx y del
        lado de Pilot en `AI-VL-ecosystem/docs/PUBLIC_ACCESS.md`; endurecido: `/docs` y
        `/openapi.json` eran públicos (sacados), test que llama TODAS las rutas sin credencial,
        CSP/HSTS/headers, `TRUSTED_PROXIES` (en `~/.pilot/pilot.env`), con SSO la contraseña solo
        desde la red de la empresa. **Falta:** el server block del nginx + certbot (quien lo
        administra), `TRUSTED_PROXIES`, la dirección pública en Pilot, el registro en Entra, y
        corregir el mail del owner (`silk-techonogies.com`, con `pilot_admin.py set-email`).
        **2026-10-29, desde las PCs de la oficina no resuelve** (`ERR_NAME_NOT_RESOLVED`): la
        oficina usa el DC `silk-dns` (192.168.12.100), autoritativo de una zona interna
        `silk-technologies.com` (split-horizon) que tiene `splunk` → 192.168.12.102 pero no
        `pilot` (ni `www` ni `zammad`). **RESUELTO ese día:** el usuario creó A `pilot` → 192.168.12.102 en ese DC (verificado;
        el nginx sirve Pilot por nombre en esa IP, 200).
        **2026-10-28, revisión de seguridad con Pilot ya en internet** (pruebas desde afuera +
        auditoría del código). Desde afuera, bien: todo 401 sin sesión, WebSockets 403, rate
        limit del nginx corta en el 11.º pedido, TLS 1.2/1.3, headers, la IP del cliente real
        llega (181.47.17.238 desde casa; la oficina por hairpin se ve como 192.168.12.1).
        Arreglado ese día: **(a) CRÍTICO** — `GET /api/classes?model=` (permiso `view`) y el
        `model` del hub llegaban crudos a ultralytics, que baja cualquier `https://`/`gs://` y
        abre el `.pt` con pickle → ejecución de código en esta PC para cualquier invitado; ahora
        iacore acepta solo los nombres que lista `/options` (`_yolo_model`). (b) Cambiar la
        dirección pública pasó de admin a owner (`manage_org`): el SSO manda a todos ahí.
        (c) Microsoft se matchea por `preferred_username` (UPN, dominio verificado), nunca por
        `email` (atributo mail, sin verificar: "nOAuth"). (d) El executor rechaza una URL de
        relay con saltos de línea (escribía claves arbitrarias en su `.env`).
        También ese día: el H.264/WebRTC negocia por Pilot (`/api/whep/{robot}`), se acabó el
        "Open this once and accept the certificate"; desde internet sigue cayendo a intra
        hasta que el Meraki reenvíe UDP+TCP 8189 a 192.168.20.99 (mediamtx ya anuncia
        201.216.197.132, hecho 2026-10-28). Las miniaturas de
        Fleet salen de Frigate, una por robot (antes solo el último abierto, el del bridge).
        **Abierto, fuera de Pilot:** el **puerto 22 de 201.216.197.132 llega por SSH a
        ticktera** (misma clave de host que 192.168.12.102) **y acepta contraseña** — es la
        máquina que publica Pilot, Splunk y Zammad. Sacar el reenvío del 22 en el Meraki (o al
        menos `PasswordAuthentication no` + llaves). La clave de `maxi` pasó por un chat: cambiarla.
        Menores sin tocar: auditoría sin tope (filas por intentos fallidos), `imgsz`/`num_ctx`
        sin límite para operadores, `CORS_ORIGINS=*` en `run.sh` (inofensivo sin credenciales,
        innecesario en un solo origen), iacore sigue en `0.0.0.0` sin credencial en la LAN.
        3. **Antes de publicarlo a internet** (lo que sigue abierto): Pilot mueve robots. Hoy solo el login cuida la
           puerta del navegador, e iacore/executor/mediamtx siguen sin credencial en la LAN
           (ver "Queda abierto aparte"). Decidir si se publica a internet o solo por VPN/Tailscale.
  - [ ] **Fase 4 — empresarial (resto)**: segundo factor TOTP,
        recuperación de contraseña por mail, sesiones activas con "cerrar en todos lados",
        visor del registro de auditoría.
  - [ ] **Queda abierto aparte** (iacore resuelto 2026-10-29, b610cb8: `run.sh` lo levanta en
        127.0.0.1, `IACORE_HOST` lo abre): iacore (`:8001`), el executor y mediamtx siguen sin
        credencial en `0.0.0.0` (§7.1 "Token en el borde de servicio"); el login cubre solo la
        puerta del navegador. Los scripts de banco que leen `/ws/view`
        (`robot-video-pipeline/tests/video-bench/`, `_latency_probe.py`) ahora reciben 4401:
        necesitan una credencial con permiso `view`, y la device key solo tiene `ingest`
        (API keys con rol de lectura: fase 2).
- [ ] **Producto: cómo se entrega, se licencia y se instala en los robots** (pedido
      2026-10-26: "no que clone el GitHub"; "que no se lo pueda comprar alguien y pasárselo a
      otro"). Decisiones en `ROADMAP.md` §9. Nada construido todavía; va **después** de las
      fases de usuarios.
  - **Entrega (decidido): instalador + Docker.** Una imagen por pieza (backend+front, iacore
    con CUDA y modelos, executor/bridge, mediamtx) en un registro privado de Silk; un
    `install-silk-pilot.sh` que revisa el servidor (Ubuntu, GPU NVIDIA, driver, Docker), baja
    las imágenes con la licencia del cliente (o las carga de un `.tar` para sitios sin
    internet) y deja servicios que arrancan solos; `silk-pilot update` en vez de `git pull`.
    Linux solamente (DDS con red del host, ROS2, CUDA: un `.exe` sería WSL2 y el DDS ahí no
    anda). El instalador termina mostrando `https://<ip>:8443/setup?code=XXXX-XXXX`: quien
    instaló es quien tiene acceso al servidor, así que el código llega precargado y el paso
    "Verify server" desaparece para el cliente (el campo manual queda de respaldo). Vender la
    caja ya armada (appliance) queda **abierto**; usaría el mismo instalador adentro.
  - **Código (decidido): Nuitka primero, PyArmor si Nuitka rompe** (torch/ultralytics son el
    riesgo). Se hace al armar las imágenes. Más contrato/EULA (a ver con un abogado).
  - **Licencia (propuesta, a confirmar):** como Splunk — por tiempo (anual), con límites
    (robots, usuarios). Archivo de licencia **firmado por Silk** (Ed25519; el servidor trae
    solo la clave pública y verifica sin internet). **Activación de un solo uso:** el cliente
    recibe una clave; al instalar, el servidor genera un install ID (huella de la máquina +
    azar), la clave + el ID se cambian en el portal de Silk por la licencia atada a esa
    máquina, y la clave queda gastada. Copiar la app a otro servidor no sirve: la licencia no
    valida ahí. Sin internet: el instalador muestra un código de pedido y la licencia vuelve
    como archivo. Al vencer: aviso 30 días antes y gracia; después se bloquean las sesiones
    nuevas y el manejo, **nunca** se corta un robot en movimiento. Cambio de hardware =
    reactivación (N transferencias por licencia). La verificación vive en código compilado
    (por eso Nuitka). Hace falta un portal/servidor de licencias de Silk (pieza nueva).
  - **Instalación en los robots (abierta):** hoy es `git pull` + systemd a mano en el Jetson
    del Go2 (video, telemetría, relay) y en el PC2 del G1. Propuesta: un **agente de robot**
    (imagen Docker por modelo; el Jetson del Go2 ya corre Docker, ThousandEyes) que se
    **enrola** desde la app: "Add robot" (fase 3) genera un token de un solo uso y muestra
    un comando para pegar en el robot, o el servidor lo instala él mismo por SSH con las
    credenciales del robot. El agente queda con su propia device key (como el camera
    bridge), se actualiza desde el servidor y cuenta para el límite de robots de la licencia.
    Para los primeros clientes, instalación hecha por Silk (servicio) mientras tanto.
    **2026-10-26 (usuario): igual hacer un instalador de robot aunque lo corramos nosotros**,
    para que sea fácil y para ir probándolo. Lo que corre en los robots hoy **no es todo C++**:
    en C++ están los que hablan DDS con el robot (`robot-command-relay/src/*_sender.cpp`,
    `g1_joint_bridge`, los `*_telemetry_reader.cpp`), compilados **en el robot** con
    `build.sh` contra el SDK de Unitree, o sea que el fuente está ahí; en Python están el relay
    HTTP (`relay_server.py`: allowlist, clamp, dead-man), el shipper de Splunk, el lector de
    GPS y el pipeline de video (`camera_source.py`, `mjpeg_server.py`), más scripts de
    GStreamer. Para no dejar código legible: el C++ se compila **antes** (imagen de build
    arm64 con el SDK; al robot van solo binarios stripped) y el Python con Nuitka para
    aarch64, igual que en el servidor. El instalador se corre desde el servidor Pilot, copia
    por SSH una versión armada (con número de versión y commit de origen), instala los
    servicios systemd y escribe la device key del robot. **Regla actual** ("código al robot
    solo por `git pull`", para que el robot no se desvíe de git): **sigue vigente hasta que
    exista el instalador**; el usuario está de acuerdo con que después sea "solo por el
    instalador", porque cada versión sale de un commit identificado.
  - **Versiones y actualizaciones (pedido 2026-10-26: "tagueo el commit y hago el .apk en el
    CI/CD", servidor y robots, con notificaciones).** Propuesta:
    - **Release = tag.** Versión semántica `vX.Y.Z`. Como son varios repos, el repo
      `AI-VL-ecosystem` lleva un **manifiesto de release** que fija la versión de cada pieza
      (backend, frontend, iacore, executor/bridge, agente de robot por modelo); taguear ese
      repo es sacar una versión de Silk Pilot.
    - **CI/CD al taguear** (los repos ya tienen `.github/workflows/ci.yml`): corre los tests,
      arma las imágenes Docker del servidor y los paquetes del robot (arm64, C++ compilado,
      Python con Nuitka), los **firma** (cosign o minisign) y los publica en el registro privado
      de Silk junto con el manifiesto firmado (versión, fecha, notas, checksums, versión mínima
      de agente que acepta el servidor).
    - **El servidor busca actualizaciones** una vez por día en el servidor de Silk
      (autenticado con su licencia) y, si hay una nueva, **avisa en la app a admins y owners**
      ("Silk Pilot 1.4 disponible", con las notas). Actualizar es un botón o
      `silk-pilot update`: respaldo de la base antes de migrar, chequeo de salud después y
      **vuelta atrás automática** si falla. Sin internet: subir el archivo del update.
      Canales `stable` y `beta`.
    - **Robots:** cada agente informa su versión; Fleet muestra los desactualizados o
      incompatibles con el servidor, y el update del robot se dispara desde la app **solo con
      el robot quieto y desarmado**, nunca en movimiento, conservando la versión anterior
      para volver atrás.
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
- [ ] Micrófono y parlantes del robot — **plan del Go2 en `roadmap/GO2-AUDIO.md` (§5.8), 2026-10-14**.
- [x] **Que la IA conteste rápido** — hecho 2026-10-16: 6.8 s → 0.6 s hasta la primera palabra.
      Ollama corría el encoder de visión en la CPU; ahora `run.sh` levanta un llama-server
      propio con la app. Medición y tabla en `BITACORA.md` §10 (2026-10-16). Modelo: Qwen3-VL 4B
      Q4 con 1024 tokens por foto, contra 7 candidatos más. Pendiente: `run.ps1` (Windows) no lo
      tiene. Whisper ya va en la GPU (2026-10-16): `small` int8, 0.16 s y 2.6 %
      de error contra 0.47 s y 8.0 % del `base` en CPU (30 voces argentinas, `BITACORA.md` §10).
- [x] **La voz leía "asterisco asterisco"** — arreglado 2026-10-16: el VLM contesta en markdown y
      las tres voces leían los símbolos. `AI-VL-frontend/src/lib/speakable.ts` limpia cada frase
      antes de hablar (pedirle texto plano al modelo empeoró la lectura: leyó "Fluke" donde dice
      Chauvin Arnoux, 3 de 3). En pantalla el texto sigue con su formato.
- [x] **Pausa larga después de cada punto con Kokoro (em_santa)** — arreglado 2026-10-16: no era la
      voz (su audio trae ~0.1 s de silencio) sino la cola, que pedía la frase siguiente recién
      cuando terminaba la actual: síntesis de Kokoro ~0.4 s + ida y vuelta. Ahora la siguiente se
      sintetiza mientras suena la actual (`speechQueue.ts`, con tests).
- [x] **Selector de voces y voz de Drive** — 2026-10-16: el selector mostraba decenas de voces
      "system" del navegador; ahora solo las del servidor (Piper y Kokoro), y las del navegador
      solo si el servidor no tiene ninguna. La voz elegida es una para toda la app
      (`AI-VL-frontend/src/lib/voiceChoice.ts`): el parlante del robot en Drive no mandaba voz y
      hablaba siempre con la default del servidor (Daniela).
- [x] **Identidad del asistente** — 2026-10-19: toda pregunta libre lleva "You are Bender, a Unitree G1
      humanoid robot made by Maxi. The image is what your own camera sees in front of you."
      (`config.json` `assistant_persona`, por robot), agregada al final de la instrucción, nunca
      mezclada. Pasó de "parece que te están viendo" a "Sí, estoy viendo tu mano" y de "Soy Qwen" a
      "Soy Bender… fabricado por Maxi", sin romper 17.84 kW ni Chauvin Arnoux.
- [ ] **Medir bien la identidad (pedido 2026-10-19):** troubleshooting con más fotos reales del G1 y
      más variantes. Lo visto: una versión larga leyó 17.84 como 1784; "speak of yourself as I"
      rompió todo; la elegida a veces dice "Tengo un spray" en vez de "Tenés". Correr el set de
      `vlm_server_benchmark.py` (hechos + comandos) con cada variante antes de cambiarla.
      Medido después (6 intentos, display del C.A 8220): **17.84 kW** sin identidad 6/6, con la
      identidad corta 3-5/6 a 1152 px pero 6/6 a 1500 px; **21.65 kVA 0/6 en TODAS** (lee 2165 o
      2.165): el punto decimal de ese display es el límite del modelo, no de la identidad. Los
      datos (amigo, hermano, altura, trabajo, creador) ahora los elige iacore por palabra clave
      — el modelo los recitaba todos y ninguna redacción lo frenó.
- [x] **Bender tranquilo, la hora y respuestas cortas** — 2026-10-19 (iacore 7e6301b, frontend
      f28c955). Solo el nombre "Bender" ya le contagiaba el personaje de Futurama ("¡Ay, qué
      miedo!"); la identidad ahora dice "a calm and helpful robot, not the cartoon character" y
      sacó "Unitree G1" (con el modelo en la identidad: 2/6 en 17.84 y perdía el nombre); el
      modelo pasa a ser un dato por palabra clave. Medido: 17.84 kW 6/6, y a "estás en el medio"
      contesta "No, no estoy impidiendo el paso. Estoy aquí para ayudarte". La hora es un dato
      con `{now}` (hora local de la PC). La brevedad NO va en el prompt (una frase "sé breve" dio
      0/6 en 17.84): al hablar se dicen ~90 palabras (la frase que las cruza se termina) y después
      "El resto lo tenés en la pantalla". Primero fue un tope de 3 frases y cortaba las listas
      (cada ítem es una frase: "En la mesa veo" quedó en dos objetos); arreglado el mismo día. Los
      "..." ya no cortan frases: se dicen como una pausa.
- [ ] **Bender útil — plan para implementar (pedido 2026-10-19: "todo eso").** Todo en iacore, que
      ya arma la pregunta (`free_prompt_system`); el front y el backend no cambian salvo donde se
      dice. Cada pieza entra como un DATO más por palabra clave, igual que la hora: nada se le
      agrega al prompt si la pregunta no lo pide (lo medido: cada frase de más rompe lecturas).
      Antes y después de cada pieza, correr `src/vlm_reading_check.py` (ver abajo) — si baja,
      no entra.
      1. **Buscar en internet** — **hecho 2026-10-28** (`search_common.py`, SearXNG en
         `deploy/searxng`, 127.0.0.1:8095): dólar blue $1.550 con fuente, lluvia 28 % con fuente,
         ~1-2 s más solo en las preguntas que buscan. Cuándo buscar: pedido explícito ("buscá",
         "search") → sí; señala lo que se ve ("el cartel", "esto") → no; el resto lo decide el
         propio llama-server con una pregunta de texto (medido: 42/42 sobre preguntas mezcladas,
         ~26 ms); sin modelo, palabras clave en español e inglés. Para fechas, resultados y
         cifras lee las 3 primeras páginas (River: "1 de Nov. Boca v River 3:00 PM" de ESPN). Las
         preguntas de internet van sin la imagen. Plan original: SearXNG local en docker (sin clave, sin cuota; Brave o Tavily
         solo si SearXNG no alcanza). `search_common.py`: se busca solo con "buscá",
         "averiguá", "en internet", noticias, clima, precios, "quién es/qué es" + algo que no
         está en la imagen; 3-5 fragmentos con fecha y fuente van como dato; la respuesta dice
         de dónde salió. Medir: segundos que agrega (se espera 1-2 s) y acierto con/sin.
      2. **Base de datos — los tres tipos:**
         - a. ✅ **batería, carga, temperatura del pack, enlace y latencia — hecho 2026-10-28**
           (backend `robot_watch.state` → iacore `state_facts`, solo cuando se pregunta por él:
           "¿cuánta batería tenés?" → "82%"). Falta: temperaturas de los motores (solo existen con
           la pestaña Joints abierta), fallas, historial por Splunk.
           **Datos del robot**: batería, temperaturas, estado, fallas. En vivo del relay
           (`/health` y el estado que ya lee el executor), no de una base; el historial ("¿cuántas
           veces se cayó hoy?") por la API REST de Splunk, con la cuota de 500 MB/día en mente.
         - b. **Documentos propios (RAG)**: manuales y fichas de equipos en PDF → trozos →
           embeddings locales en CPU (multilingual-e5-small o bge-m3) → `sqlite-vec`. Se cruza con
           la lectura: "¿está bien que marque 250?" contra el rango de la ficha.
         - c. ✅ **Memoria del robot — hecho 2026-10-28** (backend `memory.py`, pestaña Memory):
           "guardá esta imagen" / "acordate que…" en los dos idiomas, por robot, la ve todo el
           equipo; las notas vuelven al asistente ("¿dónde está la llave?" → "en el cajón de
           arriba"). Falta: personas (punto 3) y el registro de charlas.
           **Memoria de personas y charlas**: SQLite (personas, notas, lo que se le pidió
           recordar, registro de charlas). "Bender, acordate que…" guarda; "¿qué te dije
           ayer?" busca.
      3. **Reconocer personas ("ver a alguien y decir quién es").** Detector YuNet + SFace de
         OpenCV (Apache 2.0, CPU, liviano) — NO los modelos de InsightFace (licencia solo
         investigación). Alta desde la app o por voz: "Bender, este es Mateo" guarda el
         embedding de la cara en la base de 2c; al preguntar "¿quién soy?" o "¿quién está
         ahí?" el nombre entra como dato. Local siempre, con consentimiento y botón para
         borrar a alguien. Medir con fotos reales del G1: aciertos, falsos positivos, umbral.
      4. **Que lo que dice lo mueva — DESPUÉS (usuario 2026-10-19: "por ahora no").** Ya existe el
         intérprete (`command_common.interpret`, la pestaña Robot command); falta que un
         "command" del oído vaya ahí además de al VLM, con Safe mode y la lista de skills
         permitidas; "estás en el medio" → correrse.
- [ ] **El asistente como un LLM de verdad — para cuando haya una GPU mejor (pedido 2026-10-28).**
      Hoy **cada pregunta va sola** (verificado 2026-10-28): a `/api/vlm/stream` le llegan el
      cuadro actual, la pregunta y la identidad (`VlmStreamRequest`: image, prompt, robot); la
      conversación se guarda (`chats.py`) solo para mostrarla. "¿Y la pared?" funciona porque
      vuelve a mirar, no porque se acuerde. La idea del usuario: "que sea como hablar con
      cualquier LLM". Lo que falta:
      1. **Contexto de la conversación** — **hecho en texto 2026-10-28** con el 4B y la ventana
         de 4096: la conversación abierta va con cada pregunta (`history`), los turnos más
         nuevos que entran en 5000 caracteres (`vlm_common.history_messages`); probado: "¿de qué
         color es?" y "lo que dijiste primero" las entiende, primera palabra 0.7 s igual que
         sin contexto. Falta: las imágenes de turnos viejos y ventanas más grandes (GPU nueva);
         la búsqueda web usa la pregunta anterior solo cuando la actual no trae tema ("buscalo",
         "buscá eso", "look it up": hecho 2026-10-28); una que trae tema a medias ("¿y quién
         juega mañana?", "cuánto cuesta uno") se busca literal, sin el tema de antes —
         reescribir la consulta con el modelo usando la conversación. Para probar con más ventana: `VLM_MODEL=…2B… VLM_MMPROJ=…
         VLM_CTX=8192 ./linux/run.sh`. **Medidor de memoria (2026-10-28)**: cada respuesta
         termina con una marca `usage` (tokens del prompt según llama-server, ventana de
         `/props`, turnos enviados de los que hay) y el chat muestra "Memoria: 2.6k de 4.1k
         tokens · quedan 1.5k"; cuando los turnos viejos ya no entran avisa "Ya no recuerda las
         primeras N preguntas" con "Empezar otra". Medido en el 4B: ~1.2k la primera pregunta
         (casi todo el cuadro), ~300 más por turno. Desde la tarde del 2026-10-28 el historial
         llena la ventana (`history_budget`: ventana − 512 para la respuesta − cuadro − sistema;
         el cuadro se calcula por tamaño, 1 token por bloque de 32×32, piso 1024): con un cuadro
         de 1600×1200 recuerda 11 turnos; antes olvidaba con 1.3k libres. Lo olvidado se ve
         apagado con una línea "ya no recuerda lo de arriba". La búsqueda también entiende
         preguntas mixtas ("¿cuánto cuesta este multímetro?": el modelo mira el cuadro y arma
         la consulta "Fluke 87V precio"), 12/13 medidas. Lo que quedaba: cada pregunta lleva los turnos anteriores (texto y,
         donde sirva, las imágenes de esos turnos), con un tope por tokens. Es lo que encarece:
         más prefill por respuesta y más memoria de GPU para el contexto (hoy la 5060 de 8 GB
         está justa: VLM 4.4 + iacore 1.7, ver §7.6). Medir segundos hasta la primera palabra
         con 0 / 4 / 10 turnos.
      2. **Pasarle fotos**: adjuntar una imagen propia (subida o del celular) además del cuadro
         de la cámara, y preguntar sobre ella.
      3. **Memoria fuera de las conversaciones**: una base de datos propia, no el chat.
         "Guardá que…" / "acordate de…" guarda; "¿te acordás de…?" busca y entra como dato.
         Es la pieza **2c** de "Bender útil" (arriba), ahora pedida también desde el chat de la
         app y no solo por voz.
      4. **Reconocer personas**: mostrarle la foto de alguien con su nombre y que después lo
         reconozca al verlo. Es la pieza **3** de "Bender útil" (YuNet + SFace, local, con
         consentimiento y botón para borrar).
      Orden sugerido: 3 y 4 no necesitan la GPU nueva (la memoria es SQLite, las caras corren
      en CPU); 1 y 2 sí, por el contexto.
- [x] **Cómo habla el asistente** — 2026-10-28 (iacore b6b3bb2). `src/vlm_chat_check.py`: 87
      respuestas (qué está viendo, la imagen, él mismo, la hora, conocimiento, comentarios,
      saludos, gracias, ruido de Whisper, conversaciones) con chequeos sin temas (emoji,
      asteriscos, saludo, repregunta, idioma, largo, describir la imagen ante un comentario,
      copiar una respuesta anterior, "estás mostrándome"). Un clasificador de texto (~27 ms)
      separa charla de pregunta sobre la imagen; solo la charla lleva la regla de estilo,
      porque aplicada a todo bajó la lectura de 93 % a 79 %. Resultado: 46 % → 79 % de
      respuestas limpias, lectura igual (93 %). **Todo cambio de prompt se mide con los DOS
      chequeos.** Falta: las repreguntas al final en respuestas sobre la imagen ("¿Quieres saber
      algo más?", 16 %), y probar el modelo nuevo con los dos bancos cuando llegue la GPU.
      Segunda vuelta (iacore 70b1bc6): "te estoy mostrando / que ves" también señalan la imagen,
      se sabe robot con cuerpo, saluda de vuelta, las respuestas con búsqueda no repreguntan
      (0/51). Medido todo de nuevo: lectura 93 %, charla ~80 % (186 respuestas, 2 pasadas).
      **HECHO 2026-10-29 (10819a5):** la consulta la escribe el modelo con la conversación
      (preguntas Y respuestas, 3 turnos) y la fecha de hoy — `write_query`, ~130 ms; con imagen,
      `identify_query` también ve la conversación. Banco de seguimientos: regla vieja 5/12,
      modelo 12/12. De punta a punta: "¿el anterior a éste?" tras León XIV → "Francisco"; "¿y
      cuánto sale?" tras "Galaxy S24" → busca el S24; "este control" con la charla del Papa
      atrás sigue buscando el control que se ve.
      Límites del 4B: identifica el mismo castillo como Osaka, Himeji o Matsumoto; "no tengo
      piernas" para el G1.
- [ ] **Prueba de lectura del VLM** — `AI-VL-core/src/vlm_reading_check.py` (2026-10-19): 57
      preguntas con respuesta conocida sobre las 33 fotos de `fotos/` (las 9 de equipos y 3
      escenas de Descargas ahora están ahí: `clean/23-31`, `scenes/`), por la misma función que
      usa la voz, con la identidad de Bender, 3 intentos con cuadro fresco, 1152 px.
      **Primera corrida: 159/171 (93 %), 53 de 57 siempre bien — idéntico SIN identidad**, así
      que Bender no le cuesta nada a la lectura. Las 4 que nunca acierta (límite del modelo):
      la aguja del manómetro Beyca (dice ~250, está en 0), **21.65 kVA** (lee 2165), los
      prensaestopas de `clean/25` (dice 16, son 4) y la marca chica "Spectra" (lee "EPCIA").
      Lee bien: Fluke 438 y 87V, C.A 8220 (17.84 / 12.26), Hanna 9033, Hach 2100Q, HM PH-200,
      Smart Sensor AR8100, PCE-VM 20, ABB, Contatec, Micro-Epsilon, Steck, Soldexel, De Wit,
      JMP, el 650.0 °C y la emisividad 0.95. Correrla antes de tocar prompt, identidad, modelo o
      tamaño de imagen; resultados en `docs/MODEL_BENCHMARKS.md` §4.
- [ ] **Voces nuevas para probar (2026-10-19).** Piper no tiene nada mejor en español (las que
      faltan son x_low/low) y Kokoro tiene solo las 3 que ya están. Lo nuevo:
      - **Supertonic 3** (66M, ONNX, CPU, licencia OpenRAIL): NUEVO, 10 voces (M1-M5, F1-F5),
        las 10 entendidas palabra por palabra por Whisper, ~1.3 s por 8 s de audio. El acento
        no está evaluado: hay que escucharlas.
      - **Pocket TTS 3.3** (Kyutai, CPU): ya medido el 10-16 con lola; ahora sus otras voces
        (charles, marius, javert, giovanni) también hablan con el modelo español y se
        entienden; primer audio a 0.08 s en streaming, 3.4× tiempo real. Clonar una voz
        propia (una voz "de Bender" grabada) pide aceptar la licencia en Hugging Face.
      - Qwen3-TTS y Chatterbox: no entran en la 5060 junto al VLM (ver MODEL_BENCHMARKS §3).
      - Para escuchar y marcar favoritas: https://claude.ai/artifact/JYzpraNQ9pVckm2j7SraEj
        (24 voces, misma frase, mismo volumen, con lo que entendió Whisper). Archivos en
        `AI-VL-core/results/tts_samples/new_2026-10-19/` (misma frase;
        `now_*` son las voces actuales para comparar).
      - [x] **Supertonic en la app** — 2026-10-19 (iacore 6f8274b): elegidas de oído M1, M2, M3,
        F2 y F4 (más Davefx y Alex, que ya estaban). Tercer motor en `tts_common`, nombres
        `supertonic-*`, mismo volumen que Kokoro, a 22.05 kHz con filtro (el emisor del G1
        remuestrea lineal). Los instaladores bajan el modelo a `supertonic_models/`.
      - [x] **Voz por defecto: Alex (Kokoro `em_alex`)** — 2026-10-19, elegida por el usuario "porque
        es la que mejor pronuncia" (iacore 29cde8e, launchers a70c7c7). El frontend caía a la
        primera voz de la lista (Daniela) e ignoraba el default del server: arreglado (a7ca72a).
        Quien ya había elegido una voz en el navegador la conserva.
- [ ] El VLM se niega a adivinar nacionalidad por la cara (entrenamiento de Qwen, no nuestro prompt).
      Probado 2026-10-16: una instrucción "sin sermones" no lo cambia y rompe la lectura de marcas;
      queda el prompt original. Solo estima con pistas visibles (bandera, camiseta, carteles).
- [ ] Mejorar el TTS — **medido 2026-10-16**: la voz de hoy (Piper `es_AR-daniela-high`) es la
      que peor se entiende (34 % de error al re-transcribirla, el resto 6-9 %; dijo "420" por
      "trescientos veinte"). Muestras de 12 voces para elegir de oído en
      https://claude.ai/artifact/WQdyGJR4CcvioadcyCz8za. Falta que el usuario elija.
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
- [x] **HECHO 2026-10-29 (unitree_ros2 802f0e3).** Destrackear `unitree_ros2/dds.env` — se escribe en runtime por `POST /dds`, así que cada
      cambio de red desde la UI ensucia el repo.
- [x] **Ya estaba hecho (frontend 4ebfda3 "english!"), verificado 2026-10-29.** Traducir **2** strings en español del frontend — **[blocker]** por la regla de idioma.
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
- [x] **Convención de ramas** — 2026-10-19: todos los repos en su principal (`main`, o `master` en
      `robot-ecosystem` y `robot-command-relay`); `unitree_ros2` usa `main` para lo nuestro y deja
      `master` como copia de Unitree. Ver `ROADMAP.md` §0. Las ramas viejas siguen existiendo.
- [x] ~~`AI-VL-frontend` en `feature/both-robots-same-tiem`~~ — resuelto 2026-10-19: los cuatro
      repos de AI-VL trabajan en `main`.
- [ ] **Cerrar `ARQUITECTURA_ROBOT_G1_PROPUESTA.md`**, que la cabecera del ROADMAP daba
      por borrado desde el 28-08 y sigue trackeado (ver el aviso al principio de `../ROADMAP.md`). Antes de
      borrarlo hay que sacar las dos referencias vivas: `AI-VL-ecosystem/ROBOT_CONTROL.md` y
      `docs/G1_FASES_Y_CREAR_SKILLS.md`. Si algo suyo todavía vale, sube a §6; si no, se borra
      y git lo recuerda.
- [ ] Sacar las 14 menciones de `192.168.123.99` de los docs (§3).
- [ ] **Margen de VRAM en la PC de la app — anotado 2026-10-27, NO tocar todavía (decisión del
      usuario).** La pantalla completa nativa de Pilot congela **todo** Firefox cuando la GPU se
      queda sin memoria: cada congelamiento de ese día fue una ráfaga `NVRM ... Out of memory
      [NV_ERR_NO_MEMORY]` en `journalctl -k` (12:10, 12:14, 12:40), y ninguna en otro momento.
      Al cambiar a pantalla completa (o volver) el escritorio pide una superficie nueva del tamaño
      de la pantalla y no hay lugar. Reparto medido (8 GB): llama-server 4.4 GB (Qwen3-VL-4B
      Q4_K_M + mmproj F16, `-c 4096`), iacore 1.7 GB con yolo11x a 960 px (0.5 GB recién
      arrancado, sin YOLO), escritorio + VS Code + Warp + Firefox ~1.1 GB → 7.5 GB. La página no
      puede liberar memoria de otros procesos, así que el arreglo es dejar margen fijo. Opciones,
      de menor a mayor cambio, **sin medir cuánto libera cada una**: (1) que iacore suelte YOLO
      cuando nadie detecta, (2) un YOLO más chico por defecto (11s/11m), (3) achicar el VLM.
      Mientras tanto la pantalla completa nativa queda **prendida a propósito**
      (`AI-VL-frontend/src/lib/screen.ts`); si molesta, sacar `enterScreen()` de los que la llaman
      y queda solo la expansión dentro de la página, que no pide VRAM. Diagnóstico ante cualquier
      congelamiento del navegador en esa PC: `journalctl -k | grep NV_ERR_NO_MEMORY` y
      `nvidia-smi` primero.

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

**Es un script, no un bloque para copiar y pegar:**

```bash
~/Desktop/.claude/check.sh           # herramientas + lint + tests + grafo (rápido, local)
~/Desktop/.claude/check.sh --net     # + Splunk HEC y Frigate
~/Desktop/.claude/check.sh --gate    # + pre-commit (stagea y puede REESCRIBIR archivos)
~/Desktop/.claude/check.sh --all     # todo
```

Sale con código != 0 si algo está en rojo, así sirve de gate. Nada necesita el robot.

> **Por qué dejó de ser prosa (2026-09-22).** Vivía acá como 40 líneas de bash dentro de un
> `.md`, y la prosa no se ejecuta: se pudre callada. La primera vez que se corrió entera a
> mano salieron dos defectos con semanas de antigüedad —`python3 -m pytest` fallaba en los dos
> repos que tienen venv, y el conteo de tests del §2 estaba **71 atrás** (decía 175, eran
> 246)—. Por eso el script **mide** el total y lo compara contra lo que el ROADMAP §2 declara,
> en vez de que alguien lo escriba a mano.

Dos cosas que el script **no** puede chequear, porque se cargan al arrancar la sesión: que
`/mcp` muestre `codebase-memory-mcp` **connected**, y que el hook de reindex dispare al inicio
(si no, abrir `/hooks` una vez recarga la config). Y una tercera, que es de método: la frescura
del grafo **no** la mide `detect_changes` — se verifica buscando con `search_graph` un símbolo
recién escrito.

---
