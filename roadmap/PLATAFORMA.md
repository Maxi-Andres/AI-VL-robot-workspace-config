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

- [ ] **Pasada completa de UI y UX de la app** (pedido 2026-10-20, para después). No un arreglo
      puntual: revisar las cinco pestañas (Live, Drive, Robot, Video, Joints) como un todo —
      jerarquía visual, densidad del header, consistencia de controles y estados, flujos que no
      se entienden. Absorbe a los ítems sueltos de UX de esta lista (vista de VLM, pill de
      estado, SAFE_MODE en rojo, selección de robot global). Ya hecho como punto de partida:
      logo de Silk en el header (frontend `6ab8ba2`, `2e35f21`). Pendiente parecido en Splunk:
      un ícono de carga más visual que el texto "cargando" (`GO2.md` §5.6).
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
      1. **Buscar en internet.** SearXNG local en docker (sin clave, sin cuota; Brave o Tavily
         solo si SearXNG no alcanza). `search_common.py`: se busca solo con "buscá",
         "averiguá", "en internet", noticias, clima, precios, "quién es/qué es" + algo que no
         está en la imagen; 3-5 fragmentos con fecha y fuente van como dato; la respuesta dice
         de dónde salió. Medir: segundos que agrega (se espera 1-2 s) y acierto con/sin.
      2. **Base de datos — los tres tipos:**
         - a. **Datos del robot**: batería, temperaturas, estado, fallas. En vivo del relay
           (`/health` y el estado que ya lee el executor), no de una base; el historial ("¿cuántas
           veces se cayó hoy?") por la API REST de Splunk, con la cuota de 500 MB/día en mente.
         - b. **Documentos propios (RAG)**: manuales y fichas de equipos en PDF → trozos →
           embeddings locales en CPU (multilingual-e5-small o bge-m3) → `sqlite-vec`. Se cruza con
           la lectura: "¿está bien que marque 250?" contra el rango de la ficha.
         - c. **Memoria de personas y charlas**: SQLite (personas, notas, lo que se le pidió
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
