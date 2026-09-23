# ROADMAP — la fuente de la verdad

**Escrito el 2026-08-28. Revisado contra el código el 2026-09-10; §2, §4, §5.2, §10 y §11
actualizados el 2026-09-14, 15 y 16 (video: latencia MEDIDA, y el reescalado MJPEG bajado de 105 a 29 ms).** Reemplaza y absorbe:
`.claude/STATE.md`, `AI-VL-ecosystem/docs/CONTROL_POR_VOZ_G1.md`,
`AI-VL-ecosystem/docs/ARQUITECTURA_ROBOT_G1_PROPUESTA.md` y
`robot-splunk-docs/Telemetria-Splunk.md`.

> ⚠️ **Tres de los cuatro están borrados; el cuarto no.** Verificado el 2026-09-10:
> `ARQUITECTURA_ROBOT_G1_PROPUESTA.md` **sigue existiendo y sigue trackeado** (15 KB), y lo
> citan `AI-VL-ecosystem/ROBOT_CONTROL.md` y `docs/G1_FASES_Y_CREAR_SKILLS.md`. O sea: el
> quinto backlog que este documento venía a eliminar sigue en pie y con dos referencias
> vivas. Pendiente en §7.6.

Antes había **seis backlogs** que se contradecían entre sí. Este es el único — y desde el
**2026-09-22** está partido en cinco archivos por tipo de contenido, no por robot. El mapa
está abajo, en §0.

---

## 0. Cómo leer esto

El ROADMAP —este archivo más los cuatro de `roadmap/`— es la autoridad sobre **qué hay que
hacer y en qué orden**. No sobre *por qué*: eso vive en los documentos de datos, que siguen
intactos porque son evidencia medida y están citados desde el código. Lo que tenés abierto es
la mitad de **orientación**; las listas de trabajo están en `roadmap/`, y el mapa está más
abajo en esta misma sección.

| Autoridad sobre | Documento |
|---|---|
| Qué hacer, en qué orden, y el estado real | **este archivo** |
| Por qué el DDS no cruza de subred, y por qué dos robots no conviven en un segmento | `robot-splunk-docs/RED-Y-DDS.md` |
| **Por qué el robot caminaba a tirones, y por qué la latencia del enlace se multiplicaba** | **`robot-splunk-docs/FRENO-INYECTADO.md`** — medido 10-09, arreglado, **falta re-medir sobre LTE y Starlink** |
| **Cada número de video, con fecha, hora, configuración y estado del enlace** | **`robot-splunk-docs/MEDICIONES.md`** — el registro; si un número no tiene fecha y enlace al lado, no sirve |
| **Que YOLO no frene al `/drive`, y que las cajas correspondan al cuadro que se ve** | **`AI-VL-ecosystem/docs/PLAN_YOLO_FRAME_PAIRING.md`** — diseñado 09-16; **backend construido y probado el 09-22** (§4 items 1-5, 7 tests, verificados rompiendo el código a propósito). Faltan los items 6-7, el emparejado en el NAVEGADOR para H.264 — **a propósito**: el §7 nuevo del mismo plan los reemplaza a medias |
| **Que YOLO y el VLM analicen la imagen que está SELECCIONADA en `/live`, no la que eligió el código** | **`AI-VL-ecosystem/docs/PLAN_YOLO_FRAME_PAIRING.md` §7** — pedido el 2026-09-22, **decidido el mismo día: UN solo selector**, el análisis sigue a la pantalla. Falta diseñarlo y construirlo. Hoy la fuente está fija: con H.264 elegido, el operador mira una imagen y pregunta por otra |
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
| Qué puerto usa cada máquina y qué cruza el enlace de campo | `robot-splunk-docs/PUERTOS.md` |

### Dónde vive cada cosa — el ROADMAP se partió el 2026-09-22

Este archivo era de **1150 líneas** y mezclaba cuatro cosas distintas: orientación, la lista de
trabajo de cada robot, el trabajo de plataforma que no depende de ningún robot, y la bitácora
histórica. La bitácora es la que crece sin techo y la que menos se lee, así que era la que
menos sentido tenía dentro del archivo que se abre todos los días.

| Archivo | Qué tiene | Cuándo se lee |
|---|---|---|
| **este** (`ROADMAP.md`) | §0 cómo leer · §1 los dos robots · §2 estado real · §4 qué bloquea · §9 decisiones abiertas | **siempre, primero** |
| `roadmap/GO2.md` | §5 — Track A, el Go2 | cuando se trabaja en el Go2 (hoy, el foco) |
| `roadmap/G1.md` | §6 — Track B, el G1 | cuando se retome el G1 |
| `roadmap/PLATAFORMA.md` | §7 app y seguridad · §8 tooling y health check | trabajo que no toca ningún robot |
| `roadmap/BITACORA.md` | §3 correcciones · §10 observaciones de campo · §11 lo ya descartado | cuando hace falta saber **por qué** algo es como es |

> 🛑 **La excepción: `BITACORA.md` §11, "lo ya descartado".** Es la única parte de la bitácora
> que hay que leer ANTES y no DESPUÉS: son ~30 caminos que ya se probaron y fallaron, cada uno
> con su motivo medido. Si vas a proponer algo de video, de red o de medición de latencia,
> revisalo primero — está lleno de ideas que suenan bien y ya costaron una sesión cada una.

**La numeración de secciones no cambió**, así que cualquier `§5.2` ya escrito en un doc o en un
comentario del código sigue resolviendo. Solo hay que saber en qué archivo está, y eso es la
tabla de arriba.

> **Regla que evita que se vuelvan a mezclar:** un hallazgo medido va a la **bitácora**, con su
> fecha. Las listas de trabajo dicen únicamente **qué hacer**, y apuntan a la entrada de
> bitácora que lo justifica. Lo que engordaba este archivo era escribir las dos cosas en el
> mismo lugar cada vez que se medía algo.

**Convención de ramas (2026-09-10):** `dev` es desarrollo; **el robot y cualquier despliegue
usan la rama principal**. Se mergea `dev` → principal (por PR) y el robot hace `git pull`
como siempre. Aplicado el 10-09 en los **tres repos de código del robot**, y solo en ésos.

Estado real de las 11 ramas, verificado el 2026-09-10 — la convención está a medias:

| Repo | Rama hoy | |
|---|---|---|
| `robot-video-pipeline`, `robot-telemetry-agent` | `main` | ✅ convención aplicada |
| `robot-command-relay` | **`master`** | ⚠️ el único con `master`; hay que unificarlo desde GitHub |
| `robot-ecosystem` (umbrella), `robot-splunk-docs` | `dev` | ⚠️ sin mergear a la principal |
| `unitree_ros2` | `feature/dev2` | ⚠️ y tiene código que corre en el robot |
| `AI-VL-ecosystem` + `AI-VL-core` + `AI-VL-backend` | `feature/both-robots-same-time` | — |
| `AI-VL-frontend` | **`feature/both-robots-same-tiem`** | ⚠️ typo, ver §7.6 |
| `unitree_sdk2` | vendor | — |

Las dos que muerden: `master` vs `main` y el typo del frontend **rompen cualquier `for` sobre
los repos**, que es exactamente como está escrito el health check de §8.

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
## 2. Estado real — verificado el 2026-09-10

*(Las filas de video, robot, HEC, tests y comandos se recomprobaron el 10-09 contra los
servicios vivos; el resto viene del 09-04.)*

| Capacidad | Estado | Verificado cómo |
|---|---|---|
| Telemetría Go2 → Splunk | **construida** — agente C++ + shipper + unidad systemd | `robot-telemetry-agent/src/telemetry_reader.cpp` lee `LowState`; `shipper/hec_shipper.py`; unidad presente |
| HEC de Splunk | **abierto y sano** | `192.168.20.200:8088` responde `{"text":"HEC is healthy","code":17}` |
| Video: mitad del robot | **construida** — encode por hardware + push RTMP | `robot-video-pipeline/robot/run-video.sh` con `nvv4l2h264enc` |
| Video: mitad de HQ | **corriendo** — mediamtx + Frigate 0.14.1 | contenedor `frigate` healthy, mediamtx en `:8554/:8888/:8889/:1935` |
| Video: el stream | **FUNCIONANDO — y desde el 2026-09-14 por el H.264 NATIVO del Go2**: 1280x720 a **14.25 fps**, 1.78 Mbps | `SOURCE=multicast` lee RTP en `230.1.1.1:1720` y lo pasa **sin decodificar ni re-encodear**. 3.2× los cuadros por 1.24× el ancho de banda, 2.5× más eficiente por cuadro, y el Jetson sin trabajo de encoder. Antes: 1080p a 4.5 fps por el videohub. Detalle en `PLAN-VIDEO.md` §3 |
| **Video: la latencia** | **MEDIDA 2026-09-15 — ~100-235 ms, y nunca hubo un problema de latencia** | MJPEG directo del robot **235-300 ms** (instrumentado, dos corridas). La rama H.264 **no se puede instrumentar desde un script**: el unico cliente disponible es OpenCV, que arrastra el defecto de la fila de abajo — el navegador es el unico instrumento, y da **~100 ms con multicast** y ~200 con videohub. El "~650 ms del videohub" era un error de reloj (el mismo método dio -710 y -1400 ms, imposibles) y además **no cabe en el total**. Método: `latency_clock.py` — una página que servimos nosotros, con reloj y un panel que parpadea, filmada por la cámara; los dos extremos son nuestro reloj. `PLAN-VIDEO.md` §1 y §9 |
| **Video: el reescalado del MJPEG** | **ARREGLADO 2026-09-16 — de 105 ms a 12.8 ms (8.2×), máximo de 194 a 17.8, y la CPU del proceso de 22.4% a 3.0%** | No era el reescalado: el trabajo real son 28 ms y los otros 77 eran **CPU congelada**. `robot-video.service` tenía `CPUQuota=50%` sobre el cgroup entero (los tres procesos del pipe comparten presupuesto) y el kernel lo probaba: `nr_throttled` 14059 de 30418 períodos, **46% congelados**. Arreglado cambiando `CPUQuota` (techo absoluto) por `CPUWeight=50` (peso relativo, solo muerde bajo contención). Dos arreglos: la cuota (105→29.4) y el reescalado en los motores NVJPG del Orin NX (29.4→12.8). `PLAN-VIDEO.md` §6.c |
| **Video sobre LTE** | ⚠️→✅ **Depende del día del enlace, y eso es el hallazgo.** Con RTT 165-384 ms no alcanzaba (`/drive` 4.0 fps, H.264 3.7). Con RTT 43 ms y **3.12 Mbps medidos con iperf3**, el `/drive` va a **14.3 fps con 89 ms** de latencia. | Enlace: RTT 165-384 ms, ~0.93 Mbps. **La limitación es la PÉRDIDA, no el ancho de banda**: a 4.2 KB por cuadro usamos 0.09 de 0.93 Mbps. Curva medida: cap 5 fps entrega 3.85, cap 8 entrega 3.35, cap 15 entrega **1.90** — **mandar más entrega menos**, porque cada pérdida frena todo el stream TCP. Y bajar fps agrega hueco entre cuadros (250 ms a 4 fps), así que **no hay perilla que resuelva**. `PLAN-VIDEO.md` §6.d |
| **Video: SRT sobre LTE** | ✅ **FUNCIONA — 2026-09-16, triplicó los cuadros por el mismo ancho de banda** (H.264 3.71 → **11.00 fps**, tráfico 0.71 → 0.74 Mbps, colas TCP en cero) | La curva se dio vuelta y eso confirma el diagnóstico: con TCP pedir 15 fps entregaba **1.90**; con SRT entrega **11.00**. Mismo enlace, misma hora. SRT recupera lo que entra en su presupuesto de 150 ms y descarta el resto (medido: 15 perdidos, 21 recuperados, **6 descartados** de 2707). Cadena: robot `srtsink` → `srt-bridge :8891` → `udp:9000` → mediamtx. `PLAN-VIDEO.md` §6.d |
| ~~**Video: SRT sobre LTE (pendiente)**~~ | *(resuelto, ver fila de arriba)* | `srtsink` en el robot ✅, `PROTO=srt` en `run-video.sh` ✅, `srt-bridge` en HQ **corriendo hace 2 días** ✅. Falta que el `mediamtx.yml` de PRODUCCIÓN ingiera lo que el puente emite: `source: udp+mpegts://127.0.0.1:9000`, línea que **solo está en el yml de prueba**. SRT recupera lo que entra en su presupuesto de 150 ms y **descarta el resto en vez de bloquear**, que es exactamente lo que TCP no hace. `PLAN-VIDEO.md` §6.d |
| **Video sobre Starlink — la rama de manejo se corta** | 🟡 **MEDIDO 2026-09-23, arreglo IMPLEMENTADO, falta probarlo en el robot** | Latencia buena (79 ms p50 a QP40) pero **10 cortes de 250-916 ms en 150 s, todos del enlace**: TCP congela el stream hasta retransmitir cada paquete que Starlink pierde (3.4-4%, en ráfagas en los cambios de satélite). Pasado a **UDP con una paridad por grupo** (`/h264?udp=`, `H264_UDP_PORT` en el bridge, apagado por defecto): en loopback con 4% de pérdida entrega 95% de los cuadros exactos y sin congelar. Además: sacar el MJPEG y QP 36→40 recuperó el NVR de 2.46 a 11.74 fps. `PLAN-VIDEO.md` §6.i, `MEDICIONES.md` 2026-09-23 |
| **Video: leerlo con OpenCV** | ⚠️ **DEFECTO ABIERTO** — `cv2.VideoCapture("rtsp://mediamtx")` entrega cuadros de **2455 ms** de antigüedad | Constante desde el primer cuadro, no se acumula. El MISMO stream sale por WebRTC en 200 ms y por el ffmpeg de Frigate en 1475 ms: **escala con el cliente, no con el stream**. Descartados con medición: opciones de FFmpeg (todas), TCP vs UDP, hilos, `writeQueueSize` de mediamtx (y bajarlo rompió a Frigate). Sin causa raíz. `PLAN-VIDEO.md` §6.b |
| Video: el lector del bridge | **cerrado el 2026-09-14 — no era lo que parecía** | El "lector 12.91 fps de una fuente de 14" era el transitorio de arranque (2.35 s de abrir RTSP + 2.39 s esperando el primer IDR) dentro de un promedio acumulado. En régimen consume **14.23 fps, la tasa exacta de la fuente**. Lo roto era un `STREAM_URL` apuntando al MJPEG que `SOURCE=multicast` apaga. `PLAN-VIDEO.md` §6 |
| **Comandos: micro tirones al caminar** | **DIAGNOSTICADO y ARREGLADO el 2026-09-10 — falta re-medir sobre LTE y Starlink. 2026-09-23: `move` por UDP + dead-man 1 s implementados, sin probar en el robot (`FRENO-INYECTADO.md` §7.2)** | **No era el jitter, y no era el video: era un defecto de 2 líneas que AMPLIFICA la latencia del enlace.** El `RelayTransport` posteaba un `stop_move` antes de cada `move`, y como ese POST es bloqueante y `_start_move` lo espera con un `join`, **la ventana de frenado ≈ RTT + 9 ms**. Medido con sniffer sobre `tcp/8092`, 30 s de teleop real: **154 de 155 moves (99%) precedidos por un freno**, 320 comandos donde alcanzaban 155. En cable son 15 ms de un ciclo de 155 (10%, imperceptible); sobre LTE a 46/95 ms son 55–104 ms (35–67%) — **el robot frena más de lo que camina**. Por eso el síntoma desapareció solo al pasar a cable, sin que nadie arreglara nada. Análisis completo, aritmética y protocolo de re-medición: **`FRENO-INYECTADO.md`** |
| Relay de comandos | **construido** — allowlist + clamp + dead-man | `robot-command-relay/relay_server.py` + tests |
| Control por voz, una acción | **funcionando** en el Go2 | `docs/COMO_USAR_VOZ_ROBOT.md`, `robot_executor` |
| Control por voz, secuencia | **no existe** | el intérprete devuelve **un** skill, no una lista |
| Persistencia de la app (Redis/Mongo) | **no existe** | `grep -riE 'redis\|pymongo\|mongo\|minio'` en AI-VL → 0 hits |
| Tests | **246 pasan, 6 xfail estrictos** (medido 2026-09-22: executor 61+2 · camera_bridge 62+1 · relay 48+2 · video-pipeline 48+1 · backend 17 · iacore 10). Antes: 175 y 6 el 09-14, 107 y 6 antes. ⚠️ **El número llevaba 71 tests de atraso**, y lo destapó correr el health check de §8 a mano: camera_bridge subió 24→62, relay 39→48, video-pipeline 31→48, backend 10→17 (7 son los del emparejado de YOLO). Nadie lo actualizó porque **el health check vive como prosa en un `.md` y la prosa no se ejecuta** | corrido el 2026-09-14 con el bloque de §8. El salto de 107 a 175 es sobre todo relay (6→39) y video-pipeline (9→31); camera_bridge subió 11→24, cinco de ellos del guardián de atraso del lector RTSP. El xfail que desapareció es el del `RelayTransport`, arreglado el 09-10 — ver §7.1 y `FRENO-INYECTADO.md` |
| Commit gate | verde en los 7 repos con código | `pre-commit run` rc=0 en los 7 |
| Robot | **EN LÍNEA y redesplegado 2026-09-09** — en campo, por el túnel del IR1101 | `10.1.254.18` responde; los tres servicios `active`. `.123.18` no responde porque no estamos en su LAN |
| **GPS del robot** | **hardware disponible, sin configurar** — antena activa + módulo celular en el IR1101 | el chasis base del IR1101 **no** tiene GNSS: lo da el módulo. Plan en `PLAN-CONECTIVIDAD-ROBOTS.md` **Fase 6** |
| **Telemetría CURWB en Splunk** | **existe y nadie la había registrado** — `index=wlc9800`, sourcetype `cisco:urwb:telemetry`, 55 MB/día desde `192.168.20.20`; más 83 MB/día del WLC 9800 | `license_usage.log` el 2026-08-31. Son los radios del enlace del G1 (§1): material para el pendiente de validación §6.4 |
| **Licencia de Splunk** | **RESUELTA 2026-09-04** — Partner NFR Enterprise, **50 GB/día**, vence 2027-09-04. `licenseState: OK` | el archivo llegó **traducido al español** por el navegador (6 features + un espacio en la firma) y hubo que reconstruirlo. **Pedirla siempre como adjunto `.license`.** No va al repo: es público. Detalle en `LICENCIA-Y-THOUSANDEYES.md` §2.1.e-bis |
| ThousandEyes — paneles | **en el dashboard del Go2, filtrados al Go2** — token `te_agent` define el agente en un solo lugar | org propia `SILK TECH SRL - 178`, región US2. **Un solo test involucra al robot**: `Agent to Agent Test`. De 34 tests de la org, el puente trae 8 (los de red) |
| ThousandEyes — camino oficial | **bloqueado por infra** — TE exige 443 + cert de CA pública + DNS resoluble, y valida el alcance al crear el stream | no alcanza abrir `:8088`: hace falta reverse proxy + NAT + allowlist de 12 IPs. **Plan completo: `LICENCIA-Y-THOUSANDEYES.md` §5** |
| ThousandEyes — puente | **corriendo** — `robot-splunk-docs/te-poller/`, unit `te-poller` **en esta PC** (`active`+`enabled`), **19 tests**, ruff limpio. **Temporal por diseño** | consumo medido **<5 KB/día**. Emite los mismos nombres y unidades que el exportador oficial → los paneles no distinguen la fuente. Además emite el **inventario del agente** (`thousandeyes:agent`), que el stream oficial NO reemplaza. Falta probar un reboot y mudarlo al server |
| **Dashboard del Go2** | **funcionando** — 16 paneles: telemetría, foto, cámara MJPEG, enlace TE y estado del agente | refresh por tipo: singles 10 s · tablas 20 s · gráficos 30 s · TE 60 s. La cadencia la marca el test de TE (120 s), no el refresh |
| **Dashboards de Splunk — limpieza** | **hecha 2026-09-22** — de 16 a **4 propios**; el resto eran backups fechados, dos `(v2)` duplicadas, una `(v3)` y dos `zz test color`. Vista y archivo del repo ahora se llaman igual | quedan 4 de owner `nobody` que **no se pueden borrar**: viven en `apps/search/default/`. Backup previo en el server: `~/dashboards-backup-2026-09-22-1333.tgz`. Mapeo en `robot-splunk-docs/dashboards/README.md` |
| **Dashboard `Silk HQ — Meraki`** | **recibiendo datos desde 2026-09-22** por la pata de API. Faltan syslog y webhooks, que son config del lado Meraki. **2026-09-23: al `meraki-hq.xml` (el Classic) se le puso la topología viva** del mismo estilo que el del Go2 — 6 búsquedas de token, 25 tokens, SVG animado, encabezados de sección. Verificado rasterizando el SVG con los dos estados (todo sano / como está hoy). **Versionado, NO desplegado todavía** | el informe asumía org `Silk Technologies` y red `Silk HQ`: **ninguna existe**. Real: org `Silk-Technologies` id 610420 (la key ve 4 orgs, 2 de otros clientes), redes `Silk Lab` e `Itinerante`. Detalle: `robot-splunk-docs/INTEGRACION-MERAKI.md` |
| **Meraki — poller** | **CORRIENDO contra la API real 2026-09-22** — `robot-splunk-docs/meraki-hq/`, 6 familias, **25 tests**, ruff limpio. Primera pasada: **66 eventos**, spool vacío, el índice pasó de 0 a datos | desplegado en el server (`~/robot-splunk-docs/meraki-hq`), key en `~/.meraki_api_key` 600. **Falta instalar la unit systemd** — requiere sudo, quedó sin hacer. `apptraffic` da 0: *Traffic analytics* apagado en las 4 redes |

---
## 4. Lo que bloquea ahora

1. ~~**El robot está apagado.**~~ Volvió el **2026-09-09** y está en campo, alcanzable por el
   túnel en `10.1.254.18`. Lo que sigue bloqueado por *no tenerlo al lado*: el primer `move`
   supervisado y la validación de CURWB con el cable desenchufado.
2. ~~**`REDEPLOY-EN-EL-ROBOT.md` sin ejecutar.**~~ ✅ **HECHO el 2026-09-09**, contra el robot
   real y por primera vez. Los tres servicios quedaron `active`, el video llega y la
   telemetría también. El runbook tenía **tres errores** que se corrigieron sobre la marcha:
   clonaba la rama por defecto (atrasada 3-8 commits) en vez de `dev`; daba la IP de LAN en
   vez de la del túnel; y no avisaba que **los `.env` rescatados traen rutas del repo viejo
   adentro**, que fue lo que tiró abajo el relay.

3. ~~**El glass-to-glass del video.**~~ ✅ **MEDIDO el 2026-09-15: ~100-235 ms según el camino.** Ya no
   bloquea nada, y la conclusión es que **el video nunca fue el problema**. Lo que sí queda
   abierto es un defecto del lado del cliente: leer mediamtx con OpenCV cuesta 2.4 s fijos
   (§2 y `PLAN-VIDEO.md` §6.b). No bloquea la teleoperación —`/drive` en MJPEG va a 235 ms y
   en H.264 a ~200— pero **sí bloquea mover YOLO y el VLM a H.264**, porque ambos comen del
   bridge y el bridge es el que paga esos 2.4 s.

4. **ThousandEyes por el camino oficial** necesita DNS público, certificado de CA pública,
   reverse proxy en 443 y NAT — o sea, gente de infraestructura. Mientras tanto corre el
   puente `te-poller` (§5.6). Plan de migración: `LICENCIA-Y-THOUSANDEYES.md` §5.

*(La licencia de Splunk dejó de bloquear el 2026-09-04: Partner NFR, 50 GB/día.)*

Todo lo que **no** necesita robot está en §7 y §8, y es lo que conviene hacer mientras.

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
| **GPS: cómo llega el NMEA a Splunk** — receptor propio vs input UDP vs app IOx | abierta — recomendado el receptor, mismo patrón que `te-poller` | `PLAN-CONECTIVIDAD-ROBOTS.md` §6.4 |
| **GPS: cómo se sujeta la antena al Go2** | abierta — el imán no pega, es mecánico | `PLAN-CONECTIVIDAD-ROBOTS.md` §6.2 |

Sobre el transporte, un matiz que hay que tener presente: `ROBOT_CONTROL.md` fase 2 pide
construir el ejecutor **abstraído del transporte** *"para que ROS2/Nav2 pueda entrar después"*,
y la fase 7 (navegación) **usa ROS2**. O sea: migrar al SDK nativo **eliminando** el camino
ROS2 choca con la fase 7. Abstraer y dejar los dos, no.

---
