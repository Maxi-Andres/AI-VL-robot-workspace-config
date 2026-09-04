# ROADMAP — la fuente de la verdad

**Escrito el 2026-08-28.** Reemplaza y absorbe: `.claude/STATE.md`,
`AI-VL-ecosystem/docs/CONTROL_POR_VOZ_G1.md`,
`AI-VL-ecosystem/docs/ARQUITECTURA_ROBOT_G1_PROPUESTA.md` y
`robot-splunk-docs/Telemetria-Splunk.md` (los cuatro borrados; están en el historial de git).

Antes había **seis backlogs** que se contradecían entre sí. Este es el único.

---

## 0. Cómo leer esto

Este documento es la autoridad sobre **qué hay que hacer y en qué orden**. No sobre *por qué*:
eso vive en los documentos de datos, que siguen intactos porque son evidencia medida y están
citados desde el código.

| Autoridad sobre | Documento |
|---|---|
| Qué hacer, en qué orden, y el estado real | **este archivo** |
| Por qué el DDS no cruza de subred, y por qué dos robots no conviven en un segmento | `robot-splunk-docs/RED-Y-DDS.md` |
| Tasas y tamaños reales de los 122 tópicos del Go2 | `robot-splunk-docs/CENSO-GO2.md` |
| Qué IP es cada una y en qué archivo se cambia | `robot-splunk-docs/IPS-Y-DONDE-CAMBIARLAS.md` |
| Por qué se corta el video del robot (falla también en la app de Unitree) | `AI-VL-ecosystem/docs/CORTES_DE_VIDEO_Y_SOBRECALENTAMIENTO.md` |
| Red, VPN, IR1101, transporte de campo | `robot-splunk-docs/PLAN-CONECTIVIDAD-ROBOTS.md` |
| Contrato de datos del colector y el agente | `robot-splunk-docs/PLAN.md` |
| Diseño técnico del control del G1 (fórmulas, clientes del SDK, qué no rehacer) | `AI-VL-ecosystem/ROBOT_CONTROL.md` |
| Arquitectura de la app AI-VL | `AI-VL-core/docs/ARCHITECTURE.md` §1-9 |
| El estándar de ingeniería (con el incidente detrás de cada regla) | `.claude/skills/cr/references/standard.md` |
| Runbook para poner el robot al día tras el renombre | `robot-splunk-docs/REDEPLOY-EN-EL-ROBOT.md` |
| Licencia vencida (31/08) y alta de ThousandEyes | `robot-splunk-docs/LICENCIA-Y-THOUSANDEYES.md` |

**Regla de mantenimiento:** si este documento y otro se contradicen, gana este — y el otro
está roto y hay que arreglarlo. Si algo se termina, se tacha acá, no en cinco lugares.

---

## 1. Los dos robots no son lo mismo

Esta es la distinción que faltaba en todos los docs viejos, y la que explica por qué el
trabajo se bifurca.

| | **Go2** (cuadrúpedo) | **G1 Pro** (humanoide) |
|---|---|---|
| Dónde vive | **itinerante** — campo, otra oficina, en movimiento | **dentro de un sitio**, sobre CURWB |
| Enlace | **LTE o Starlink** (ver §10) | **CURWB** — Cisco Ultra-Reliable Wireless Backhaul |
| Qué se le pide | telemetría continua + video + comandos **simples** | **comandos por voz compuestos** |
| Ejemplo objetivo | *"seguime"* → fija a la persona y camina solo detrás | *"levantá esta caja y llevala a este lugar"* |
| Optimiza para | ancho de banda y tolerancia a cortes de enlace | manipulación, percepción 3D, planificación |
| Cámara | JPEG por `videohub` + H.264 nativo en `rt/frontvideostream` | MJPEG en `/frontvideostream` (msg type del Go2) |
| IP bajo nivel | `192.168.123.161` | `192.168.123.161` — **la misma, es un conflicto** |
| IP alto nivel | `192.168.123.18` (Jetson) | `192.168.123.164` |

### CURWB — por qué el enlace del G1 cambia el diseño

**CURWB** (Cisco Ultra-Reliable Wireless Backhaul) no es "la WiFi del sitio": es un **bridge
L2 transparente** que extiende el segmento `192.168.123.0/24` **por aire**. Eso es lo que lo
hace distinto de cualquier enlace del Go2, y tiene tres consecuencias:

1. **El multicast sobrevive**, así que **el DDS cruza**. El G1 puede tener consumidores que
   lean sus tópicos directamente, sin agente onboard. El Go2 itinerante no tiene esa opción:
   por LTE o Starlink hay una frontera L3 y el DDS muere ahí.
2. **No hay que cambiar nada en el robot ni en el server.** Por eso se eligió: **PC1 del G1 no
   tiene SSH en ningún puerto** (22, 2222, 8022 y 23 todos rechazados), así que su binding de
   DDS **no se puede modificar**. Solo PC2, el Jetson `.164`, tiene SSH.
3. **Sigue sin validar, y es un riesgo alto.** `PLAN-CONECTIVIDAD-ROBOTS.md` §8 lo lista como
   *"CURWB no valida sin cable → Alto: sin camino para el G1"*, con fallback a colector
   onboard. Ver el pendiente en §6.4.

> ⚠️ **La trampa que invalida la prueba:** toda medición con el cable del robot **conectado**
> no prueba nada. `192.168.123.0/24` está directamente conectada por `eth0` y el camino
> inalámbrico nunca se ejercita. Hay que **desenchufar físicamente** el cable.

**Consecuencias de diseño que salen de esta tabla:**

1. El Go2 **no puede** depender de estar en la misma red que nada. Todo lo suyo sale del robot
   hacia afuera, por HTTP largo y ruteado, nunca DDS. Eso ya está resuelto (§5.1).
2. El G1, si CURWB valida, **sí** puede tener consumidores en su misma L2 — es la única razón
   por la que su track puede saltearse el agente onboard. Si no valida, el G1 termina con la
   misma arquitectura que el Go2.
3. Los dos usan `.161` para el bajo nivel, así que **una VLAN por robot es obligatoria**
   mientras conviven. No es una preferencia.
4. El track del Go2 es *incremental sobre algo que ya funciona*. El del G1 es *construir*.

> **Nota de red:** la WiFi de robots se movió de VLAN 20 a **VLAN 51** (~2026-08-03). Hoy
> **VLAN 20 es la de servidores** — ahí viven Splunk (`.20.200`) y esta PC (`.20.99`). Los docs
> viejos que digan "VLAN 20 = robots" están vencidos.

---

## 2. Estado real — verificado el 2026-09-04

| Capacidad | Estado | Verificado cómo |
|---|---|---|
| Telemetría Go2 → Splunk | **construida** — agente C++ + shipper + unidad systemd | `robot-telemetry-agent/src/telemetry_reader.cpp` lee `LowState`; `shipper/hec_shipper.py`; unidad presente |
| HEC de Splunk | **abierto y sano** | `192.168.20.200:8088` responde `{"text":"HEC is healthy","code":17}` |
| Video: mitad del robot | **construida** — encode por hardware + push RTMP | `robot-video-pipeline/robot/run-video.sh` con `nvv4l2h264enc` |
| Video: mitad de HQ | **corriendo** — mediamtx + Frigate 0.14.1 | contenedor `frigate` healthy, mediamtx en `:8554/:8888/:8889/:1935` |
| Video: el stream | **caído** — 0 fps | API de Frigate: `"robot": {"fps": 0.0}` |
| Relay de comandos | **construido** — allowlist + clamp + dead-man | `robot-command-relay/relay_server.py` + tests |
| Control por voz, una acción | **funcionando** en el Go2 | `docs/COMO_USAR_VOZ_ROBOT.md`, `robot_executor` |
| Control por voz, secuencia | **no existe** | el intérprete devuelve **un** skill, no una lista |
| Persistencia de la app (Redis/Mongo) | **no existe** | `grep -riE 'redis\|pymongo\|mongo\|minio'` en AI-VL → 0 hits |
| Tests | **70 pasan, 6 xfail estrictos** (eran 30 y 4 antes del 28-08) | executor 24+2 · camera_bridge 11+1 · relay 6+2 · video-pipeline 9+1 · backend 10 · iacore 10 |
| Commit gate | verde en los 7 repos con código | `pre-commit run` rc=0 en los 7 |
| Robot | **apagado / fuera de red** | `.123.161` sin respuesta; único vecino en VLAN 20 es el router |
| **Telemetría CURWB en Splunk** | **existe y nadie la había registrado** — `index=wlc9800`, sourcetype `cisco:urwb:telemetry`, 55 MB/día desde `192.168.20.20`; más 83 MB/día del WLC 9800 | `license_usage.log` el 2026-08-31. Son los radios del enlace del G1 (§1): material para el pendiente de validación §6.4 |
| **Licencia de Splunk** | **RESUELTA 2026-09-04** — Partner NFR Enterprise, **50 GB/día**, vence 2027-09-04. `licenseState: OK` | el archivo llegó **traducido al español** por el navegador (6 features + un espacio en la firma) y hubo que reconstruirlo. **Pedirla siempre como adjunto `.license`.** No va al repo: es público. Detalle en `LICENCIA-Y-THOUSANDEYES.md` §2.1.e-bis |
| ThousandEyes — paneles | **en el dashboard del Go2, filtrados al Go2** — token `te_agent` define el agente en un solo lugar | org propia `SILK TECH SRL - 178`, región US2. **Un solo test involucra al robot**: `Agent to Agent Test`. De 34 tests de la org, el puente trae 8 (los de red) |
| ThousandEyes — camino oficial | **bloqueado por infra** — TE exige 443 + cert de CA pública + DNS resoluble, y valida el alcance al crear el stream | no alcanza abrir `:8088`: hace falta reverse proxy + NAT + allowlist de 12 IPs. **Plan completo: `LICENCIA-Y-THOUSANDEYES.md` §5** |
| ThousandEyes — puente | **corriendo** — `robot-splunk-docs/te-poller/`, unit `te-poller` **en esta PC** (`active`+`enabled`), **19 tests**, ruff limpio. **Temporal por diseño** | consumo medido **<5 KB/día**. Emite los mismos nombres y unidades que el exportador oficial → los paneles no distinguen la fuente. Además emite el **inventario del agente** (`thousandeyes:agent`), que el stream oficial NO reemplaza. Falta probar un reboot y mudarlo al server |
| **Dashboard del Go2** | **funcionando** — 16 paneles: telemetría, foto, cámara MJPEG, enlace TE y estado del agente | refresh por tipo: singles 10 s · tablas 20 s · gráficos 30 s · TE 60 s. La cadencia la marca el test de TE (120 s), no el refresh |

---

## 3. Correcciones — lo que los docs decían y era falso

Este es el registro de por qué hubo que reescribir. Los tres primeros son del mismo tema y se
contradecían entre sí.

| Documento | Decía | Realidad (2026-08-28) |
|---|---|---|
| `PLAN.md` §3.2 | *"El agente de telemetría: **no existe nada**. Hoy nada del stack lee `/lowstate`"* | Existe: `telemetry_reader.cpp` lee `LowState`, hay shipper y unidad systemd |
| `PLAN.md` §3.2 | *"HEC habilitado: puerto 8088 **cerrado** — verificado"* | **Abierto y sano**. El bloqueo desapareció |
| `IMPLEMENTACION.md` | *"Etapa A ⬅️ **el único bloqueo real**"* + *"falta: 1. habilitar el HEC, 4. el agente en el robot"* | Las dos cosas están hechas. La lista quedó al revés |
| `ARQUITECTURA-REMOTA.md` §4.2 | *"Hoy la captura corre en la PC del escritorio"* y *"falta hacer opcional el mediamtx local"* | La mitad del robot está construida; `SERVER_ONLY=1` ya hace opcional el mediamtx |
| `robot-video-pipeline/docs/ARQUITECTURA.md` | *"Todo corre en la PC (`192.168.123.99`)"* | La PC es `192.168.20.99` y la captura se mudó al Jetson |
| `AI-VL-core/docs/ARCHITECTURE.md` §10 | roadmap de fases 0-5 como trabajo futuro | Fases 0,1,2,4,5 **ya construidas**; solo falta la 3 (persistencia) |
| `Telemetria-Splunk.md` | plan completo con checkboxes vivos | Superado por `PLAN.md` desde el 2026-08-19. **Borrado** |
| `G1_FASES_Y_CREAR_SKILLS.md` | cita `~/Desktop/CONTROL_POR_VOZ_G1.md` | Ruta muerta desde el renombre del 27-08 |
| 4 docs de control del G1 | el mismo roadmap de fases 0-5, tres veces | Consolidado acá. Dos borrados |

**Correcciones del 2026-09-01 al 09-04** (sesión de licencia + ThousandEyes):

| Documento | Decía | Realidad |
|---|---|---|
| `PLAN.md` §5.1 | *"500 MB/día hasta el 25 de agosto"* | **50 GB/día** hasta 2027-09-04 (Partner NFR). El análisis de volumen sigue válido; el presupuesto ya no manda |
| `PLAN.md` §5.2 | *"El trial vence el 25/08"* | Venció, y **dejó la búsqueda muerta 10 días**: con la cuota en 0 el HEC siguió ingiriendo y generó **una violación por día** |
| `PLAN.md` §11 paso 13 | *"si el trial cae a Free se pierde alerting"* | Se pasó a Free y se perdió; **recuperado** con la NFR (`Alerting`, `ScheduledAlerts`) |
| `PLAN.md` §12 | *"¿cuánto consume la otra persona?"* — abierto | **~138 MB/día**, telemetría Cisco (WLC 9800 + CURWB) por HEC |
| `PLAN.md` §2.3 | el contenedor de TE del Jetson es **"(Cisco)"**, implícitamente ajeno | Está en la org **propia** `SILK TECH SRL - 178`, con admin nuestro |
| `PLAN.md` §388 | *"Contenedor ThousandEyes (IOx) en el IR1101: RUNNING"* | El agente `LAB-IR-1101` figura **offline desde ~2026-08-22**, igual que el del Jetson |
| Este documento, 2026-08-31 | *"la app de Splunkbase hace pull, no expone nada"* | **Falso**: la app no hace pull. Los **dos** caminos oficiales son push a HEC |


**Además:** 14 menciones de `192.168.123.99` siguen repartidas por los docs. Esa IP ya no
existe: esta PC es `192.168.20.99`. `IPS-Y-DONDE-CAMBIARLAS.md` ya lo sabe, el resto no.

Y las fechas de git mienten: 24 de los 50 docs muestran `2026-08-27` porque el commit del
renombre los tocó a todos. No sirven para saber qué está fresco.

---

## 4. Lo que bloquea ahora

1. **El robot está apagado.** Bloquea todo lo de campo: video, telemetría end-to-end,
   el primer `move` supervisado, el redeploy.
2. **`REDEPLOY-EN-EL-ROBOT.md` sin ejecutar.** Los clones en el robot tienen los nombres
   viejos de antes del renombre del 27-08. Es lo primero cuando el robot vuelva, y nada de
   campo funciona hasta que se haga. **Nunca se probó contra el robot real.**

3. **ThousandEyes por el camino oficial** necesita DNS público, certificado de CA pública,
   reverse proxy en 443 y NAT — o sea, gente de infraestructura. Mientras tanto corre el
   puente `te-poller` (§5.5). Plan de migración: `LICENCIA-Y-THOUSANDEYES.md` §5.

*(La licencia de Splunk dejó de bloquear el 2026-09-04: Partner NFR, 50 GB/día.)*

Todo lo que **no** necesita robot está en §7 y §8, y es lo que conviene hacer mientras.

---

## 5. Track A — Go2 itinerante

### 5.1. Telemetría — construida, sin validar end-to-end

Falta solamente cerrar el lazo, y ahora se puede porque el HEC está abierto:

- [ ] Correr el agente contra el HEC real y confirmar que llegan eventos al índice
      `go2-robot-data`. Es el único paso que queda del track entero.
- [ ] Armar el dashboard. `dashboard-go2.xml` y `dashboard-go2-sin-video.xml` existen; hay que
      cargarlos y autorizar `http://192.168.20.99:5000` en
      *Settings → Server settings → Dashboards Trusted Domains* o el panel de video queda negro.
- [ ] Cambiar la password del Jetson **antes** de dejar el token HEC ahí.
- [ ] Abrir tcp/8088 hacia `10.1.254.0/24` en el firewall de HQ (para el robot en campo; desde
      la LAN ya anda).

Presupuesto medido: **40 MB/día** contra un techo de 500 MB/día compartido. 8%.

### 5.2. Video — el stream está caído, y hay un síntoma abierto

**Primero, lo que está roto ahora mismo:** el pipeline flapea cada ~11 s. `go2_jpeg_stream`
no recibe frames, sale, ffmpeg da EOF, el supervisor reintenta. Frigate conecta y encuentra el
path vacío. Causa: no hay robot en la red **y** la unidad de usuario corre en modo captura
local en vez de `SERVER_ONLY=1`.

- [ ] Poner `SERVER_ONLY=1` en la unidad de usuario `robot-video-pipeline`. Deja de ensuciar
      el journal y es el modo correcto ahora que la captura vive en el robot. No trae video
      por sí solo.

**Después, el síntoma abierto** (de `ESTADO-Y-CONTINUACION.md` §4.4, que sigue vigente): el
video se congela ~1 s cada ~4 s. Hipótesis principal: las ráfagas de keyframe del H.264
saturan el enlace y dejan sin ancho de banda al MJPEG, que lo comparte. `IDR_FRAMES=15` con
`NVR_FPS=5` es un keyframe cada 3 s.

Experimentos en orden de costo — todos son editar `robot/video.env` y reiniciar, sin compilar:

- [ ] **`NVR_ENABLE=0`** — apaga la grabación. Prueba decisiva, cuesta un minuto.
- [ ] `IDR_FRAMES=150`. Si el período cambia, son los keyframes.
- [ ] `BITRATE=300000`. Si mejora, es contención general.
- [ ] Si se confirma: **CBR en el encoder** (`control-rate` + `peak-bitrate` en
      `nvv4l2h264enc`). Hoy el pipeline no fija `control-rate`. Es el arreglo prolijo.

> ⚠️ **Releer esto a la luz de §10.** La hipótesis de los keyframes se escribió cuando el
> enlace era Starlink. Si el problema era el enlace y no el encoder, estos cuatro
> experimentos pueden ser innecesarios. **Reproducir el síntoma sobre LTE antes de tocar
> nada.**

Lo que ya **no** es (descartado con medición): no es la cámara (12-14 fps), no es CPU (load
0,3 de 4 cores), no es el tee estrangulando, no es el descarte de frames.

Más adelante:

- [ ] **`rt/frontvideostream` leído LOCALMENTE en el robot.** El Go2 publica H.264 nativo a
      30 fps por su propio encoder. Está documentado como fallido, pero **el fracaso fue
      siempre leyéndolo desde afuera** — nunca adentro, que es un escenario distinto (bus
      interno, sin fragmentación por red). Si anda: 30 fps ya comprimido, sin polling del
      `videohub` y sin recodificar. **Es la mejora de mayor techo.**
      Existe `src/go2_h264_stream.cpp`, que quedó de aquel intento.
- [ ] El `videorate` que falta en el pipeline GStreamer del robot. El de la PC necesitó
      `-vsync cfr -r 15`; el equivalente en GStreamer nunca se aplicó. Verificar si el síntoma
      sigue antes de trabajar en esto.
- [ ] Reescalado por hardware. Hoy cv2 cuesta ~400 ms/frame.
- [ ] Decidir **video on-demand vs continuo**. Telemetría son 40 MB/día; video 1080p son
      2-4 Mbps ≈ **20-40 GB/día**. Por un enlace de campo entra, pero es otro orden de
      magnitud. Decisión a tomar antes de construir nada más.

### 5.3. Comandos — construido, sin estrenar

El relay existe con allowlist de verbos, clamp de velocidad y dead-man.

- [ ] **Primer `move` real supervisado.** Ojo: el robot **tiene que estar parado**. Echado
      (`mode: 0`, `body_height` 0.089) el servicio de sport devuelve **-1**.
- [ ] Aplicar los P0 de seguridad de §7 **antes** de este paso, no después.

### 5.4. Capacidades futuras del Go2 — comandos autónomos simples

Nada de esto está construido ni diseñado. Es el norte del Go2, distinto del G1: **no**
manipulación, sino locomoción autónoma con un objetivo simple.

- [ ] **`seguime`** — fijar (lock) a una persona y caminar detrás sola. Piezas: YOLO ya da
      la caja de la persona; falta *tracking* con identidad estable entre frames, estimación
      de distancia, y un lazo de control que mande velocidad al `SportClient` con el dead-man
      del relay. No necesita IK ni percepción 3D métrica precisa: alcanza con mantener la
      caja centrada y a un tamaño objetivo.
- [ ] Otros del mismo tipo, cuando `seguime` funcione: *"volvé"*, *"quedate"*, *"patrullá"*.

El Go2 comparte con el G1 el intérprete de comandos y el transporte, pero **no** el track de
manipulación (nada de GR00T, nada de SONIC).

---

### 5.5. Observabilidad — un tablero por robot

**Decidido el 2026-09-04.** El modelo es **un dashboard de Splunk por robot**, no uno
compartido con selector. `dashboard-go2.xml` es el primero y define el patrón:

| Pieza | Cómo se hace |
|---|---|
| Identidad del robot | token `<init><set token="te_agent">` — un solo lugar para el nombre del agente de TE |
| Telemetría | `index=go2-robot-data`, un índice y un token HEC **por robot** |
| Enlace | métricas de ThousandEyes filtradas por agente, no por test: tests nuevos entran solos |
| Estado del agente | `sourcetype=thousandeyes:agent` — el único panel que dice algo con el robot apagado |
| Video | `<img>` a Frigate, **cero licencia** |
| Foto | estático de Splunk (`/static/app/search/`), mismo origen, sin Trusted Domains |
| Refresh | por tipo: singles 10 s · tablas 20 s · gráficos 30 s · TE 60 s |

**Para el G1 se clona el XML y se cambian el token, el índice y la foto.** Lo que hace que
eso sea barato es que nada está hardcodeado por test ni por panel.

Pendiente declarado: **la estética.** El tablero prioriza que el dato esté y sea correcto;
la prolijidad visual es una pasada aparte y posterior.

> 📌 El refresh **no consume licencia** — Splunk cobra bytes indexados, no búsquedas. El
> límite real de frescura es el **intervalo del test en ThousandEyes** (hoy 120 s), no el
> refresh ni el poller. `LICENCIA-Y-THOUSANDEYES.md` §6.7.

---

## 6. Track B — G1 en sitio, comandos por voz compuestos

### 6.1. El estado real, sin adornos

Lo que existe hoy: STT, TTS, VLM, YOLO, el ejecutor, y un **intérprete que traduce una frase a
UN skill fijo**. Anda, y anda sobre el **Go2**.

Lo que no existe: que una frase se convierta en una **secuencia**. *"Levantá esta caja y
llevala a este lugar"* son cinco subtareas (`locate`, `navigate_to`, `grab`, `navigate_to`,
`place`) y hoy el intérprete devuelve una sola. **Ese salto es el track entero.**

### 6.2. Las fases

Las fases 0-2 están hechas (sobre el Go2). De la 3 en adelante es construcción.

| Fase | Qué | Estado |
|---|---|---|
| 0 | Compilar `unitree_sdk2`, correr `g1_loco_client_example` | hecho |
| 1 | Voz → intención: `POST /command`, texto → skill JSON | hecho (un skill) |
| 2 | Locomoción por voz con los clientes built-in del SDK | hecho (Go2) |
| 3 | **Percepción 3D** — bbox + profundidad + intrínsecos + mano-ojo → pose en marco pelvis | falta |
| 4 | **Skill `grab`** — IK del brazo 7-DOF + perfil de velocidad | falta |
| 5 | Integración con manejo de errores hablado | falta |
| 6 | **Planificador de instrucción compuesta** — el salto de §6.1 | falta |
| 7 | Navegación (Nav2 + SLAM), destinos semánticos | falta |
| 8 | Manipulación aprendida (GR00T + LeRobot) — reemplazo escalable de la fase 4 | falta |
| 9 | Whole-body control (SONIC) — opcional | falta |
| 10 | Integración mobile-manipulation con **arbitraje explícito** de controladores | falta |

El detalle técnico de cada pieza (la fórmula de deproyección, qué librería de IK, qué clientes
del SDK, y el inventario de *qué no rehacer*) está en `AI-VL-ecosystem/ROBOT_CONTROL.md`. No se
repite acá.

### 6.3. El enlace: validar CURWB — bloquea la arquitectura, no las fases

Esto no está en ninguna fase pero decide **cuál** arquitectura se construye (§1). Es barato y
lleva años pendiente.

- [ ] **Desenchufar físicamente el cable del robot** y recién entonces medir. Con el cable
      puesto, `192.168.123.0/24` está directamente conectada por `eth0` y el camino
      inalámbrico nunca se ejercita: la prueba da un falso positivo garantizado.
- [ ] Confirmar que el bridge L2 es transparente — **el multicast tiene que sobrevivir**.
- [ ] Contar tópicos sobre el aire:
      ```bash
      ros2 daemon stop
      ros2 topic list --no-daemon | wc -l
      ```
      Referencia: **122** tópicos desde su propia subred, **2** desde otra (`CENSO-GO2.md`).
- [ ] Si no valida: fallback a **colector onboard**, o sea la misma arquitectura del Go2 para
      el G1. Decisión, no accidente.

Procedimiento completo en `PLAN-CONECTIVIDAD-ROBOTS.md` §"Fase 4"; el riesgo está declarado en
su §8 y el pendiente también figura en `RED-Y-DDS.md` §9.

### 6.4. Riesgos declarados

- **La profundidad es el riesgo más grande** del cerebro motor. Si la cámara del G1 no da
  profundidad métrica confiable, conviene el camino de aprendizaje (ACT/GR00T), que no depende
  de deproyección precisa. Prerequisito: saber qué cámara trae el G1.
- **CURWB sin validar** — impacto alto: sin él no hay camino L2 para el G1 (§6.3).
- **PC1 del G1 no tiene SSH** en ningún puerto, así que su binding de DDS no se puede tocar.
  Cualquier diseño que necesite cambiar algo en PC1 está muerto de entrada.
- **El G1 se cae.** Siempre tiene que haber una postura de reposo alcanzable, y todo
  movimiento va detrás de un watchdog.
- La fase 7 necesita el transporte **ROS2**. Ver §9.

---

## 7. Track C — App AI-VL y seguridad

### 7.1. P0 de seguridad — verificados línea por línea el 2026-08-28

- [ ] **`SAFE_MODE` fail-safe.** `robot_executor_service.py:89` es
      `_as_bool(os.environ.get("SAFE_MODE"), False)` → **default permisivo**. Y `:1260` deja
      que un request que omite el campo tome el camino permisivo. Poner `True` en los dos
      lados y alinear el docstring de `:16`, que ya afirma lo contrario.
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

### 7.3. Los 4 xfails estrictos

Afirman el comportamiento **correcto** de defectos abiertos. `strict=True`: cuando arreglás el
defecto el test pasa inesperadamente y **pytest falla**, avisándote de borrar el marcador.
Arreglá el código, borrá el marcador — no borres el test.

| Test | Defecto |
|---|---|
| `test_move_without_continuous_is_bounded` (×2 robots) | `continuous` default `True` |
| `test_rate_limiter_does_not_allow_double_the_budget_across_a_boundary` | ventanas fijas dejan pasar 2× en el borde |
| `test_token_comparison_is_constant_time` | el relay compara el token con `==` |

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
- [ ] **`AI-VL-frontend` está en la rama `feature/both-robots-same-tiem`** mientras sus tres
      hermanos están en `...same-time`. Verificado hoy, sigue así. Va a molestar cuando los PR
      suban juntos.
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
- **Grafo**: 12 proyectos indexados, refresco en session start/stop, UI en
  `http://127.0.0.1:9749`.

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

# Tests: 24+2 y 6+2
(cd unitree_ros2/robot_executor && python3 -m pytest -q)
(cd robot-ecosystem/robot-command-relay && python3 -m pytest -q)

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

## 9. Decisiones abiertas

| Decisión | Estado | Dónde está el análisis |
|---|---|---|
| **Transporte: SDK nativo vs ROS2** | abierta, diferida a propósito | `AI-VL-ecosystem/docs/TRANSPORT_SDK_VS_ROS2.md` |
| **Cómo separar los dos robots** (dominio DDS vs interfaz) | abierta — bloquea 4 pasos | `docs/SEPARAR_ROBOTS_MULTIPLES.md` (AI-VL) y `robot-video-pipeline/docs/DOS-ROBOTS.md` (video) |
| **Video on-demand vs continuo** en campo | abierta | §5.2 |
| **Profundidad del G1**: deproyección clásica vs aprendizaje | abierta, depende de qué cámara trae | §6.3 |
| **ThousandEyes: exponer el HEC a internet** | abierta — es el único camino oficial | `LICENCIA-Y-THOUSANDEYES.md` §5.2 |
| **Los 26 tests de TE que no llegan a Splunk** (M365, DNS, BGP, page-load) | abierta — son de IT corporativo, ¿van a otro tablero? | `LICENCIA-Y-THOUSANDEYES.md` §6.1 |
| **Dónde vive `te-poller`**: esta PC vs el server de Splunk | abierta — hoy en la PC, que se apaga | `te-poller/README.md` |

Sobre el transporte, un matiz que hay que tener presente: `ROBOT_CONTROL.md` fase 2 pide
construir el ejecutor **abstraído del transporte** *"para que ROS2/Nav2 pueda entrar después"*,
y la fase 7 (navegación) **usa ROS2**. O sea: migrar al SDK nativo **eliminando** el camino
ROS2 choca con la fase 7. Abstraer y dejar los dos, no.

---

## 10. Observaciones de campo

### 2026-08-28 — Starlink parecía tener un cuello de botella; con LTE anduvo perfecto

En las pruebas de enlace, Starlink mostraba lo que parecía un cuello de botella. Al cambiar a
**LTE, funcionó perfecto**.

**Estado: preliminar.** Es una observación, no una conclusión: falta seguir probando, y no está
aislada la variable (hora del día, congestión de celda, saturación del beam, ubicación de la
antena, y el bypass de CGNAT que el IR1101 hace sobre Starlink).

**Por qué importa igual:** toca dos cosas escritas antes de saberlo.

1. El síntoma del video (congelamiento ~1 s cada ~4 s, §5.2) se diagnosticó como ráfagas de
   keyframe saturando el enlace — **sobre Starlink**. Si el enlace era el problema, los cuatro
   experimentos de §5.2 pueden ser innecesarios. **Reproducir el síntoma sobre LTE antes de
   tocar el encoder.**
2. La medición de `~353 kB/s` (2,8 Mbps) de `ESTADO-Y-CONTINUACION.md` §4.1, que ordena toda la
   config de video, se tomó sobre el enlace viejo. **Hay que re-medirla con `iperf3` sobre
   LTE.** Si el enlace real es mucho mayor, `MJPEG_WIDTH=640` y bajar el `BITRATE` dejan de
   ser necesarios.

- [ ] `iperf3` sobre LTE y sobre Starlink, misma hora, mismo punto, y anotar los dos números acá.
- [ ] Reproducir el congelamiento del video sobre LTE.

---

## 11. Lo ya descartado — no volver a intentar

Compacto de los "descartados" que estaban repartidos en cuatro docs. Cada uno tiene su motivo
medido en el doc de datos correspondiente.

| Descartado | Motivo |
|---|---|
| Pasar los tópicos DDS de un lado a otro de la red | 122 tópicos desde su subred, **2** desde otra, 3 con peers unicast. `RED-Y-DDS.md` |
| Túnel L2 para traer la red del robot | Imposible con dos robots: los dos son `.161` |
| VM collector con presencia L2 / VLAN por robot / trunk itinerante | Incompatible con que el robot esté en cualquier red |
| Agente que se suscribe a **todos** los tópicos | Rompe el presupuesto por 20-1700× y manda el video a Splunk |
| Un POST HEC por mensaje, síncrono, en el callback | Bloquea el receptor DDS y pierde muestras |
| Indexar `/rosout` | Los servicios del robot son *bare DDS apps*, no nodos ROS2: no loguean ahí |
| Instalar ROS2 en una VM nueva | Ubuntu 26.04 no tiene Humble, y `ros-humble-desktop` pelado no trae los msgs de Unitree |
| `<iframe>` en el dashboard de Splunk | El sanitizador de Simple XML de Splunk 9 los borra. Se usa `<img>` sobre el MJPEG de Frigate |
| Dashboard Studio para el panel de video | No tiene panel HTML; eso es Simple XML |
| SRT del robot a mediamtx | El robot trae **libsrt 1.4.0** y mediamtx rechaza su handshake. Se usa RTMP. Bisectado contra un listener de ffmpeg, donde sí conectó |
| `rtspclientsink` en el robot | No está instalado. De ahí RTMP |
| ffmpeg en el Jetson | No existe; hay `gst-launch-1.0` y `nvv4l2h264enc` (encoder por hardware) |
| Sacarle el "think" al VLM por config | `qwen3-vl:4b` piensa siempre. Hace falta un modelo no-think |
| LuckyEngine como fábrica de skills | Su `LimbIK` vive dentro de un DLL cerrado y no se puede reusar |
| `timechart avg(data.velocity)` sobre `/joint_states` | Es un array de N joints, no un escalar. Hay que aplanar por joint |
