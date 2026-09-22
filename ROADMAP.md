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
| **Por qué el robot caminaba a tirones, y por qué la latencia del enlace se multiplicaba** | **`robot-splunk-docs/FRENO-INYECTADO.md`** — medido 10-09, arreglado, **falta re-medir sobre LTE y Starlink** |
| **Cada número de video, con fecha, hora, configuración y estado del enlace** | **`robot-splunk-docs/MEDICIONES.md`** — el registro; si un número no tiene fecha y enlace al lado, no sirve |
| **Que YOLO no frene al `/drive`, y que las cajas correspondan al cuadro que se ve** | **`AI-VL-ecosystem/docs/PLAN_YOLO_FRAME_PAIRING.md`** — diseñado 2026-09-16, **sin implementar** |
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
| **Video: leerlo con OpenCV** | ⚠️ **DEFECTO ABIERTO** — `cv2.VideoCapture("rtsp://mediamtx")` entrega cuadros de **2455 ms** de antigüedad | Constante desde el primer cuadro, no se acumula. El MISMO stream sale por WebRTC en 200 ms y por el ffmpeg de Frigate en 1475 ms: **escala con el cliente, no con el stream**. Descartados con medición: opciones de FFmpeg (todas), TCP vs UDP, hilos, `writeQueueSize` de mediamtx (y bajarlo rompió a Frigate). Sin causa raíz. `PLAN-VIDEO.md` §6.b |
| Video: el lector del bridge | **cerrado el 2026-09-14 — no era lo que parecía** | El "lector 12.91 fps de una fuente de 14" era el transitorio de arranque (2.35 s de abrir RTSP + 2.39 s esperando el primer IDR) dentro de un promedio acumulado. En régimen consume **14.23 fps, la tasa exacta de la fuente**. Lo roto era un `STREAM_URL` apuntando al MJPEG que `SOURCE=multicast` apaga. `PLAN-VIDEO.md` §6 |
| **Comandos: micro tirones al caminar** | **DIAGNOSTICADO y ARREGLADO el 2026-09-10 — falta re-medir sobre LTE y Starlink** | **No era el jitter, y no era el video: era un defecto de 2 líneas que AMPLIFICA la latencia del enlace.** El `RelayTransport` posteaba un `stop_move` antes de cada `move`, y como ese POST es bloqueante y `_start_move` lo espera con un `join`, **la ventana de frenado ≈ RTT + 9 ms**. Medido con sniffer sobre `tcp/8092`, 30 s de teleop real: **154 de 155 moves (99%) precedidos por un freno**, 320 comandos donde alcanzaban 155. En cable son 15 ms de un ciclo de 155 (10%, imperceptible); sobre LTE a 46/95 ms son 55–104 ms (35–67%) — **el robot frena más de lo que camina**. Por eso el síntoma desapareció solo al pasar a cable, sin que nadie arreglara nada. Análisis completo, aritmética y protocolo de re-medición: **`FRENO-INYECTADO.md`** |
| Relay de comandos | **construido** — allowlist + clamp + dead-man | `robot-command-relay/relay_server.py` + tests |
| Control por voz, una acción | **funcionando** en el Go2 | `docs/COMO_USAR_VOZ_ROBOT.md`, `robot_executor` |
| Control por voz, secuencia | **no existe** | el intérprete devuelve **un** skill, no una lista |
| Persistencia de la app (Redis/Mongo) | **no existe** | `grep -riE 'redis\|pymongo\|mongo\|minio'` en AI-VL → 0 hits |
| Tests | **175 pasan, 6 xfail estrictos** (2026-09-14: executor 61+2 · camera_bridge 24+1 · relay 39+2 · video-pipeline 31+1 · backend 10 · iacore 10). Antes: 107 y 6 | corrido el 2026-09-14 con el bloque de §8. El salto de 107 a 175 es sobre todo relay (6→39) y video-pipeline (9→31); camera_bridge subió 11→24, cinco de ellos del guardián de atraso del lector RTSP. El xfail que desapareció es el del `RelayTransport`, arreglado el 09-10 — ver §7.1 y `FRENO-INYECTADO.md` |
| Commit gate | verde en los 7 repos con código | `pre-commit run` rc=0 en los 7 |
| Robot | **EN LÍNEA y redesplegado 2026-09-09** — en campo, por el túnel del IR1101 | `10.1.254.18` responde; los tres servicios `active`. `.123.18` no responde porque no estamos en su LAN |
| **GPS del robot** | **hardware disponible, sin configurar** — antena activa + módulo celular en el IR1101 | el chasis base del IR1101 **no** tiene GNSS: lo da el módulo. Plan en `PLAN-CONECTIVIDAD-ROBOTS.md` **Fase 6** |
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
| `REDEPLOY-EN-EL-ROBOT.md`, 2026-08-27 | `git clone` sin rama | Durante un tiempo la rama por defecto estaba **3-8 commits atrás** de `dev` y el clone dejaba código viejo sin fallar. **Resuelto el 10-09**: `dev` mergeado a la principal, el robot vive en `main` |

**Correcciones del 2026-09-10** (auditoría de este documento contra el código). Las cinco son
de **este archivo**, que es lo que las hace graves: la fuente de la verdad estaba desfasada.

| Decía | Realidad (2026-09-10) |
|---|---|
| Cabecera: los cuatro docs absorbidos *"borrados"* | Tres sí; `ARQUITECTURA_ROBOT_G1_PROPUESTA.md` sigue trackeado y con **dos referencias vivas**. Pendiente en §7.6 |
| §2: *"70 pasan, 6 xfail — executor 24+2"* | **105 pasan, 8 xfail** — el executor tiene 59+4. Nadie actualizó el número al agregar `test_deadman_contract.py` |
| §7.3: *"Los 4 xfails estrictos"* | Son **8**, y los dos que faltaban son **P0 en el camino del robot en campo** (`RelayTransport`). Un xfail escrito y no registrado acá es un defecto que nadie va a priorizar |
| §7.1: `SAFE_MODE` en `:89`, request en `:1260` | `:90` y `:1256`. Las cuatro de `# noqa: S104` sí estaban exactas |
| §0: *"Aplicado el 10-09 en los tres repos del robot"* | Cierto pero incompleto: `robot-ecosystem`, `robot-splunk-docs` y `unitree_ros2` quedaron fuera. Tabla completa de las 11 ramas en §0 |

**Además:** 14 menciones de `192.168.123.99` siguen repartidas por los docs. Esa IP ya no
existe: esta PC es `192.168.20.99`. `IPS-Y-DONDE-CAMBIARLAS.md` ya lo sabe, el resto no.

Y las fechas de git mienten: 24 de los 50 docs muestran `2026-08-27` porque el commit del
renombre los tocó a todos. No sirven para saber qué está fresco.

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

### 5.2. Video — anda, por el H.264 nativo. Lo que falta es MEDIR la latencia

> 🔴 **2026-09-22: el video de Frigate "cambia de color" solo — DIAGNOSTICADO, sin arreglar.**
> Mirando fijo una escena estática la imagen se va aclarando, poniendo rosa y llenando de
> ruido de croma durante ~1 minuto, y de golpe vuelve a la normalidad. **No es la cámara**
> (la primera hipótesis, el AWB/AGC del sensor, quedó refutada): es deriva del H.264.
>
> Medido sobre las grabaciones del 2026-09-21, 17:35–17:42 (`signalstats` cuadro a cuadro):
> dentro de cada GOP `Y` sube de 115.5 a 121.5, `U-128` de −4.8 a −1.9 y `V-128` de +1.3 a
> +4.1 — monótono — y en **cada IDR vuelve exactamente a los mismos valores de partida**.
> El reset cae clavado en el keyframe, y los GOP duran 47–81 s irregulares, así que no puede
> ser nada del mundo real. Par decisivo: 17:38:54 (último P) contra 17:38:56 (IDR), dos
> segundos de diferencia, rosa lavado contra imagen limpia.
>
> La causa de fondo es **pérdida de cuadros aguas abajo del encoder del robot**: `ffmpeg`
> reporta **61 `Frame num gap` por segmento** en esa franja y **cero errores de decodificación**
> — la cadena de P está rota y el decodificador no tiene cómo avisar, así que arrastra el error
> hasta el próximo IDR. Contraprueba en la misma jornada, 14:00: **11.5 fps, IDR cada 15
> cuadros (=`IDR_FRAMES`, 1.3 s), 0 gaps y 0 deriva** (`Y` varía 0.3 en 10 s).
>
> Lo que amplifica: cuando el enlace se ahoga el ritmo cae a **~1 fps**, y como `IDR_FRAMES`
> se cuenta en CUADROS y no en segundos, el keyframe pasa de llegar cada 1.3 s a cada minuto.
> El bitrate también queda mal: `ENC_BITRATE = BITRATE/NVR_FPS` divide por 5 pero llegan ~1 fps,
> así que el archivo grabado da 279 kbps contra los 2 Mbps pedidos — QP altísimo, residuos
> groseros, la deriva nunca se corrige sola.
>
> Pendiente, en orden: (1) encontrar dónde se pierden los cuadros entre `nvv4l2h264enc` y
> Frigate (sospechoso: backpressure de RTMP/TCP y las colas leaky de gst — ver `srt-sobre-lte`);
> (2) mientras tanto, bajar `IDR_FRAMES` para acotar el arrastre, asumiendo el costo de bitrate;
> (3) revisar el divisor de rate control contra el fps REAL, no contra `NVR_FPS`.
> Verificación rápida de que sigue pasando:
> `ffmpeg -i <segmento>.mp4 -vf signalstats,metadata=print -f null -` y mirar si `UAVG`/`VAVG`
> derivan dentro del GOP.

> ✅ **2026-09-14: corre `SOURCE=multicast`** — el H.264 nativo del Go2 por RTP multicast en
> `230.1.1.1:1720`, passthrough puro. 1280x720 a **14.25 fps**, 1.78 Mbps. Contra el camino
> viejo (videohub + re-encode, 1080p a 4.5 fps): **3.2× los cuadros por 1.24× el ancho de
> banda** y el Jetson sin trabajo de encoder.
>
> ❌ **No bajó la latencia.** Medido por dos métodos independientes: los dos caminos miden
> igual. La latencia está aguas arriba de ambos y **sigue sin cuantificarse**.
>
> ✅ **2026-09-15: la latencia quedó medida y el video NO era el problema.** MJPEG directo
> **235-300 ms** (instrumentado); H.264 por WebRTC **~100 ms con multicast** y **~200 ms con el
> videohub** (a ojo: no hay cliente H.264 de baja latencia fuera del navegador). Lo que costaba
> segundos era un cliente nuestro, no el robot.
>
> 🔴 **La decisión que hay que tomar es `SOURCE`, y no hay opción que gane en todo:**
>
> | | `SOURCE=jpeg` (videohub) | `SOURCE=multicast` |
> |---|---|---|
> | H.264 | 1080p, **8.5 fps**, 0.80 Mbps (el encoder del Jetson se ahoga) | 720p, **14.0 fps**, 2.12 Mbps, passthrough |
> | latencia H.264 | ~200 ms | **~100 ms** |
> | `/drive` en MJPEG | **anda, 235 ms** | **muerto** |
> | YOLO y el VLM | **andan** | **muertos** |
> | Frigate / NVR | anda | anda |
> | perilla de bitrate | `BITRATE`/`NVR_FPS`/`IDR_FRAMES` | **ninguna** |
> | carga del Jetson | decode JPEG + encode H.264 | **nada** |
>
> Cuadro completo y los matices en `PLAN-VIDEO.md` §3.3. **Multicast gana en casi todo** —el
> doble de cuadros, la mitad de latencia, el Jetson libre y el double free del encoder vuelto
> imposible— y pierde en dos: mata al MJPEG (y con él YOLO y el VLM), y **no tiene perilla de
> bitrate**, así que sus 2.12 Mbps no se pueden negociar sobre LTE.
>
> Multicast apaga el `mjpeg_server` (no hay JPEG que servir), y el bridge —que alimenta el modo
> MJPEG, YOLO y el VLM— se queda sin fuente. `/drive` en H.264 sobrevive porque va por WebRTC
> directo, sin pasar por el bridge.
>
> ⚠️ **NO apuntes el bridge a `rtsp://mediamtx` para taparlo.** Es lo que se hizo el 09-14
> (commit `791d9d8`) y metió **2.4 s** en la vista de manejo. Si hace falta que el bridge coma
> H.264, el camino es WHEP, que es el que el navegador ya usa a 200 ms.
>
> ⚠️ **2026-09-16, más tarde: MEDIDO, y el MJPEG gana por 260 ms.** Con el enlace sano
> (RTT ~45 ms) y el MJPEG destapado a 480x270 sin cap, entrega **14.31 fps a 89 ms**
> (p95 127), contra **~349 ms** del H.264 por WHEP — dos métodos independientes, el stamp del
> robot y correlación por contenido a 3.7 sigmas. Los 260 ms son el buffer de SRT (105 ms de
> `msBuf`) más encode, mediamtx, WebRTC y decode; el decode del bridge son 6.0 ms, no es ahí.
> **La regla quedó condicional: enlace sano → MJPEG; enlace con pérdida → WHEP** (ver
> `PLAN-VIDEO.md` §6.b.3). Las dos están a una línea del `.env`, y el `/drive` quedó en MJPEG.
> Lo que NO se puede es dejar las dos ramas a full: el SRT pasa de 8 a **433 descartes por
> 31 s**.
>
> ✅ **2026-09-16: el camino WHEP está HECHO y sirve para el caso malo.** El bridge puede leer
> `https://127.0.0.1:8889/robot/whep`
> (`WhepStreamSource`, con aiortc). `/drive`, YOLO y el VLM pasaron de **4.5 a 11.9 fps** y de
> 320 de ancho a **720p**, y el robot dejó de mandar la segunda copia: el MJPEG por TCP
> costaba 0.17-0.25 Mbps de una subida de ~0.93 y **era el que rompía al H.264** — sacándolo,
> las retransmisiones de SRT bajaron de 29-48% a **7.5%**. Detalle en `PLAN-VIDEO.md` §6.b.2.
>
> **Esto cambia la tabla de abajo en un punto:** la fila "`/drive` en MJPEG · muerto" de
> `SOURCE=multicast` ya no decide nada, porque el bridge no depende del MJPEG. Lo que sigue
> atado a `SOURCE=jpeg` es la **perilla de bitrate**, no la vista.
>
> ⚠️ **Antes de salir a campo con esto.** El multicast **no cruza la red** —se lee en el bus
> interno del robot y lo que sale sigue siendo RTMP unicast sobre TCP, así que NAT/LTE/Starlink
> son indiferentes—, **pero se perdió la perilla de bitrate**: en `multicast` el encoder es el
> de Unitree y `BITRATE`/`NVR_FPS`/`MAXFPS`/`IDR_FRAMES` quedan inertes. Y manda más (1.78 vs
> 1.43 Mbps, 14.25 vs 4.5 fps). Como el congelamiento acá es pérdida con retransmisión TCP, y
> mandar menos pierde menos, **sobre un enlace malo el movimiento es volver a `SOURCE=jpeg`**,
> que sigue entero. Nada se midió todavía sobre LTE ni Starlink.

**Historia, para no repetirla** — dos hipótesis centrales de este documento resultaron falsas:

| Decía | Es |
|---|---|
| "el videohub mete ~650 ms y es el 90%" | Artefacto de reloj. El mismo método dio -710 y -1400 ms, imposibles. Saltear el videohub no cambió la latencia |
| "`rt/frontvideostream` leído LOCALMENTE en el robot es la mejora de mayor techo" | **Callejón sin salida, probado adentro del Jetson** (§11). El camino bueno era el multicast |



**Cómo se llegó hasta acá (histórico, ya superado por el multicast):**

> ✅ **RESUELTO el 2026-09-09.** El video empezó a llegar: 5.1 fps por el camino del videohub.
> *(Esa cadencia es la de entonces; hoy son 14.25 fps por multicast — ver arriba.)*
>
> - [x] ~~`SERVER_ONLY=1` en la unidad de usuario~~ — aplicado como drop-in en
>       `~/.config/systemd/user/robot-video-pipeline.service.d/override.conf`.
>
> **La causa real no era solo el flapeo.** Con el robot publicando por RTMP, la unidad de
> usuario de HQ seguía en captura local y **publicaba al mismo path `robot`**. Un path de
> mediamtx admite **un solo publisher**, así que el `rtmpsink` del robot conectaba y moría
> con `Could not write to resource`.
>
> ⚠️ **Y la trampa:** `run.sh` de esa unidad **no corre solo la captura, también levanta
> mediamtx**. Pararla para liberar el path mata al receptor. El arreglo es `SERVER_ONLY=1`,
> no `stop`. Detalle en `REDEPLOY-EN-EL-ROBOT.md`.

**Lo que decía antes (histórico):** el pipeline flapea cada ~11 s. `go2_jpeg_stream`
no recibe frames, sale, ffmpeg da EOF, el supervisor reintenta. Frigate conecta y encuentra el
path vacío.

**Después, el síntoma abierto** (de `ESTADO-Y-CONTINUACION.md` §4.4). ⚠️ **Diagnosticado
desde entonces**: el congelamiento es **pérdida con retransmisión TCP**, no keyframes — el
videohub daba 0 frenadas de origen. El que lo delata es `dsack_dups`, no `rcv_ooopack`. Los
cuatro experimentos de abajo se escribieron antes de saber eso; releerlos con esa luz. El
texto original decía: el video se congela ~1 s cada ~4 s. Hipótesis principal: las ráfagas de keyframe del H.264
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

> 🔎 **Observado el 2026-09-09, sin diagnosticar:** el journal del robot tira
> `Corrupt JPEG data: premature end of data segment` cada 20-30 s de forma constante, y a
> veces `N extraneous bytes before marker 0xdN`. Es del robot leyendo **su propia** cámara
> por DDS — no es la red a HQ. Puede estar emparentado con el congelamiento de §4.4 de
> `ESTADO-Y-CONTINUACION.md`. Mirarlo cuando se retome el tema del video.

Más adelante:

- [x] ~~**`rt/frontvideostream` leído LOCALMENTE en el robot.**~~ **REFUTADO el 2026-09-14.**
      Se probó adentro del Jetson y falla igual que desde afuera: el tópico existe, nuestro
      lector **empareja** (los suscriptores suben de 1 a 2), y aun así **recibe 0 bytes y el
      callback nunca corre**. No es red ni buffers — es la deserialización del mensaje. Los
      "30 fps" que este documento citaba nunca se verificaron; lo medido por multicast es
      **14.25**. Ver §11 y `PLAN-VIDEO.md` §3.1.
- [ ] **Sin dueño `src/go2_h264_stream.cpp`**, que quedó de aquel intento. Hoy `build.sh` lo
      compila siempre, así que un error ahí rompe el build de producción. Borrarlo o dejarlo
      documentado como intento fallido.
- [ ] El `videorate` que falta en el pipeline GStreamer del robot. El de la PC necesitó
      `-vsync cfr -r 15`; el equivalente en GStreamer nunca se aplicó. Verificar si el síntoma
      sigue antes de trabajar en esto.
- [x] ~~Reescalado por hardware. Hoy cv2 cuesta ~400 ms/frame.~~ **Medido de verdad el
      2026-09-16: cv2 cuesta 28 ms, no 400.** Los 400 (y los 105 que medimos al principio) eran
      en su mayoría **CPU congelada por `CPUQuota=50%`**, no cómputo. Sacando la cuota quedó en
      **29.4 ms**. El camino por hardware sigue disponible y **validado fuera del servicio**
      (`nvjpegdec ! nvvidconv ! nvjpegenc` da **10.5 ms/cuadro**), pero ahora la ganancia es de
      17 ms sobre un total de ~250 — lo que compra de verdad es **liberar ~36% de un núcleo**.
      Dos trampas si se retoma: los caps tienen que ser `(memory:NVMM)` o el pipeline produce
      **0 bytes en silencio**, y `nvvidconv` no preserva aspect ratio. `PLAN-VIDEO.md` §6.c
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

### 5.5. GPS — hardware disponible, sin configurar

**Planificado el 2026-09-09.** Hay **antena GPS activa** (SMA, base magnética, 2.90 m) y el
**módulo celular pluggable del IR1101 está confirmado** — que es de donde sale el GNSS.

> 🔑 **El chasis base del IR1101 no tiene receptor GNSS.** Lo aporta únicamente el módulo
> celular, que trae el conector SMA `GPS`. Sin módulo la antena no va a ningún lado.

Eléctricamente la antena es casi idéntica a la `GPS-ACT-ANTM-SMA` que Cisco lista para este
router (5 V entra en su rango de bias 3–5 VDC, 29±3 dB vs 27 típ, 50 Ω). **Falta confirmar el
género del conector**: tiene que ser SMA macho.

**Lo que no es eléctrico y sí es problema:** la base magnética **no pega en el Go2** —
aluminio y plástico, sin superficie ferrosa— y hay 2.90 m de cable sobrante sobre algo que
camina.

**Las dos trampas, anotadas antes de caer en ellas:**

1. **NMEA no da grados decimales.** Viene en `ddmm.mmmm`: `3436.1234` es **34.60206**, no
   34.36. Dividir por 100 da un número plausible y **mal por decenas de kilómetros**. Misma
   clase de trampa que la latencia de TE en ms vs segundos.
2. **1 Hz es mucho más de lo necesario** (~13 MB/día). Downsamplear **en el receptor**, no en
   Splunk: la licencia cuenta bytes ingresados.

Del lado de Splunk: **no** un índice nuevo — `go2-robot-data` con sourcetype `robot:gps`,
mismo token, siguiendo la regla de un índice por robot. En el dashboard, panel `<map>` con
`geostats`, mostrando `hdop` y `sats` al lado: una posición con pocos satélites es una
posición inventada y el panel tiene que dejarlo ver.

**Receta completa, con la config del IR1101 y el orden de los 8 pasos:**
`robot-splunk-docs/PLAN-CONECTIVIDAD-ROBOTS.md` **Fase 6**.

---

### 5.6. Observabilidad — un tablero por robot

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
- [ ] **Cerrar `ARQUITECTURA_ROBOT_G1_PROPUESTA.md`**, que la cabecera de este documento daba
      por borrado desde el 28-08 y sigue trackeado (ver el aviso de arriba de todo). Antes de
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

## 10. Observaciones de campo

### 2026-09-16 — LTE: el transporte es el problema, no las perillas

Primera medición del proyecto sobre LTE. El enlace da ~0.93 Mbps con RTT de 165-384 ms, y
**no alcanza para teleoperar**: `/drive` a 4 fps, H.264 a 3.7.

> ⚠️ **Ese 0.93 era lo OBSERVADO, no la capacidad — y el mismo día el enlace dio 3.12 Mbps.**
> Medido con `iperf3` robot→HQ con el video corriendo encima: 1.67 Mbps de iperf + 0.76 del
> MJPEG + 0.69 del H.264, y es un piso. El RTT había bajado a 22.7-63.8 ms con 0% de pérdida.
> **Todo lo de abajo vale para el enlace de esa mañana, no para "LTE".**

Lo contraintuitivo, y está medido: **mandar más cuadros entrega menos**. Cap 5 → llegan 3.85;
cap 15 → llegan 1.90. No es ancho de banda (usamos 0.09 de 0.93 Mbps): es que el MJPEG va por
una sola conexión TCP, y cada pérdida cuesta un RTT de retransmisión **que bloquea todo lo que
venía detrás**.

Y la trampa no tiene salida por configuración: bajar los fps reduce la pérdida pero **agrega
hueco entre cuadros** — a 4 fps son 250 ms de espera aunque el transporte fuera instantáneo. Se
cambia una latencia por otra.

> **Sobre un enlace con pérdida, TCP es el transporte equivocado para video en vivo.** Hace
> falta uno que descarte y siga.

**Y se probó el mismo día: SRT triplicó los cuadros** (3.71 → 11.00 fps) por el mismo ancho de
banda, con las colas TCP en cero. La curva se dio vuelta: pedir 15 fps pasó de entregar 1.90 a
entregar 11.00. Faltaba **una línea** en el `mediamtx.yml` de producción
(`source: udp+mpegts://127.0.0.1:9000`), que estaba escrita y verificada en el yml de prueba
desde hacía días.

> **La lección de método:** cuando una curva de rendimiento va al revés de lo esperado —más
> entrada, menos salida— el problema casi nunca es el valor de la perilla. Es el mecanismo.
> Buscar el mecanismo antes de barrer valores habría ahorrado la mitad de la sesión.

### 2026-09-16 — sacar el MJPEG de TCP arregló el H.264, que no era lo que se buscaba

El bridge (que alimenta `/drive`, YOLO y el VLM) leía el MJPEG del robot por HTTP: una
**segunda copia** de la misma imagen cruzando el enlace. Se lo pasó a **WHEP**, que es leer el
H.264 que ya llegó, en esta misma máquina y sin tocar el robot.

Lo esperado: el bridge subió de **4.5 a 11.9 fps** y de 320 de ancho a **720p**, con deriva
0.00 s.

Lo no esperado, y es el dato: **el H.264 mejoró solo**. Las retransmisiones de SRT cayeron de
29-48% de los paquetes a **7.5%**. Los 0.17 Mbps del MJPEG no eran caros por su tamaño —eran
TCP sobre un enlace con pérdida, y cada retransmisión suya se comía la banda que el SRT
necesitaba. Eso explica el "el H.264 empeora cuando hay movimiento": el JPEG crece con el
detalle de la escena, el H.264 es CBR y no puede ceder.

> **La lección:** en un enlace saturado, las ramas no son independientes. Medir una sola no
> dice nada; la pregunta útil no era "cuántos fps aguanta el MJPEG" sino "por qué hay dos
> copias de la misma imagen cruzando el enlace".

**Y el mismo día, la corrección de la corrección.** Con el enlace sano (RTT ~45 ms, 1.48 Mbps
entre las dos ramas) y el MJPEG destapado a 480x270, el MJPEG entrega **14.31 fps a 89 ms**
contra **~349 ms** del H.264 por WHEP: **gana por 260 ms**, medido por dos métodos
independientes. Lo que costaba era el buffer de SRT (105 ms) más el encode y el jitter buffer,
no el lector (6.0 ms). **"TCP es el transporte equivocado" vale para un enlace con pérdida, no
para cualquiera** — el §6.d se midió a RTT 165-384 ms, donde el MJPEG colapsaba a 1.90 fps.

> **La lección de método, otra vez la misma:** una conclusión medida sobre UN enlace no es una
> propiedad del sistema. El enlace es una variable del experimento y hay que anotarla al lado
> del resultado.

**Y la capacidad del enlace, medida por primera vez de verdad** (antes solo se anotaba lo que
se estaba usando): `iperf3` robot→HQ con el video encima da **3.12 Mbps de subida total** —
1.67 de iperf, 0.76 del MJPEG, 0.69 del H.264— contra los **0.93 "observados"** de la mañana.
Más del triple, y sigue siendo un piso. El costo de saturar, en la misma prueba: el SRT pasó
de 7.5% a 23% de retransmisiones y de 8 a 41 descartes, mientras el MJPEG por TCP no perdió
tasa. Comando anotado en `PLAN-VIDEO.md` §6.d.

> **Y la consecuencia práctica:** "capacidad observada" NO es capacidad. Si un número de banda
> no salió de saturar el enlace a propósito, es el consumo, y usarlo como techo lleva a
> optimizar contra un límite que no existe — que es exactamente lo que se hizo media sesión.

Y el techo quedó claro: con el MJPEG afuera, el H.264 llega a HQ a **14.2 fps** contra los
14.3 que entrega la cámara. **No hay más cuadros que pedir** — `NVR_FPS` por encima de 14.3 no
hace nada. Lo que queda por gastar son bits por cuadro: hoy son 40 kbit para un 1080p, porque
`BITRATE=800000` se divide por un `NVR_FPS=20` que no existe.

### 2026-09-16 — 77 de los 105 ms del reescalado eran una cuota de systemd

Reducir el MJPEG de 1080p a 640 baja el tráfico 9× (13.79 → 1.56 Mbps) pero costaba 105 ms.
El trabajo real eran **28 ms**. Los otros 77 eran el cgroup congelado por `CPUQuota=50%`:
`nr_throttled` marcaba **14059 de 30418 períodos**. Cambiando a `CPUWeight=50` quedó en
**29.4 ms**, con el máximo de 194 a 34.5.

**El patrón, que es el que vale la pena recordar:** la cuota se puso con un comentario que
decía *"esto es barato porque va por hardware"*. Era cierto — hasta que alguien agregó un
reescalado por CPU al mismo pipeline. **Un límite dimensionado sobre una premisa sigue vigente
después de que la premisa muere, y no avisa.** El síntoma no se parece en nada a la causa: se
veía como "el reescalado es lento", y medir el reescalado aislado daba bien.

Y la distinción que lo resolvió: **`CPUQuota` es un techo absoluto, `CPUWeight` es un peso
relativo.** La intención escrita ("nada acá puede competir con el control del robot") se sirve
con el segundo; el primero congela aunque la máquina esté ociosa, que era el caso — el Jetson
estaba al 15-20% de 4 núcleos.

### 2026-09-15 — el video nunca fue el problema; era un cliente

Después de semanas de tratar la latencia como un defecto del robot, quedó medida: **~100 ms
por WebRTC con multicast, ~200 ms con el videohub, y 235 ms por MJPEG**, de la cámara a la
pantalla. No había ningún tramo oscuro aguas arriba.

Lo que sí costaba segundos era **leer mediamtx con OpenCV**: 2455 ms fijos, desde el primer
cuadro. Tres clientes del MISMO stream, a la vez: WebRTC 200 ms, el ffmpeg de Frigate 1475 ms,
OpenCV 2455 ms. **Escala con el cliente, no con el stream.**

> **La lección, que es la misma de siempre en este proyecto:** antes de atribuirle una latencia
> a un componente remoto, medí el mismo dato por dos caminos distintos. Acá alcanzó con mirar
> que el navegador viera lo mismo sin atraso — un dato que estuvo disponible todo el tiempo.

**Y una autocrítica que conviene dejar escrita:** el atraso de `/drive` lo introduje al apuntar
el bridge a RTSP para taparle la falta de fuente que dejaba `SOURCE=multicast`. Cambié "no se
ve nada" por "se ve con 2.4 s", que es peor, porque lo primero se nota y lo segundo no.

### 2026-09-14 — tres números que se daban por ciertos y no lo eran

Todo lo de abajo estaba **escrito como hecho** en algún doc, y ninguno resistió una medición.
El patrón se repite y conviene tenerlo presente: **los tres errores vienen de comparar contra
un reloj que no es nuestro, o de promediar un transitorio.**

1. **"El videohub mete ~650 ms"** — salió de mirar un cronómetro en pantalla contra el reloj
   del robot. Repetido, el método dio **-710 ms** y **-1400 ms**: negativos, o sea imposibles.
   Además, saltear el videohub entero (H.264 nativo) **no cambió la latencia**, medido por dos
   métodos independientes. El videohub no era el problema y el 650 no era un dato.
2. **"El lector RTSP lee 12.91 fps de una fuente de 14 y acumula latencia sin límite"** — era
   un promedio acumulado que se comía 4.7 s de arranque (2.35 s de abrir el RTSP + 2.39 s
   esperando el primer IDR). En régimen lee **14.23 fps, la tasa exacta de la fuente**, con
   deriva +0.0 ms/s sobre 180 s y recuperación de una demora de 12 s en menos de 2. Lo que
   estaba roto era un `STREAM_URL` apuntando a un MJPEG apagado.
3. **"Control-to-photon mide la latencia del video"** — mide lo que el operador siente
   (~1076 ms), pero **no** la del video: el robot tarda entre 311 y 1855 ms en arrancar. El
   video llega cada 70.5 ms ±4, sin ráfagas ni huecos, así que la dispersión es del robot.

> **La regla que sale de los tres:** una medición que dependa de un reloj ajeno, o que
> promedie desde antes de que el sistema esté en régimen, miente sin avisar. Las que
> sobrevivieron comparan **dos elapsed del mismo reloj** (la deriva del lector) o **dos
> extremos que son ambos nuestros** (control-to-photon).

**Y la trampa que queda abierta:** regularidad no es latencia. El `lag_s` que expone ahora el
bridge, y la regularidad de ±4 ms del transporte, prueban que **no se acumula** — no dicen
cuánto hay. Un buffer fijo de dos segundos da deriva cero. **El absoluto sigue sin medirse.**

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
      ✅ **`iperf3` instalado en las dos puntas el 2026-09-10** (3.20 en la PC, 3.7 en el
      Jetson — no pueden coincidir, y se verificó que interoperan). **Línea de base en
      cable: 42.5 Mbps de subida / 89.0 de bajada.** Detalle en `FRENO-INYECTADO.md` §7.1.
- [ ] Reproducir el congelamiento del video sobre LTE.

### 2026-09-10 — el enlace por cable, y la re-medición que queda pendiente

Con el robot en cable y el túnel arriba, el RTT bajó a **4.93 ms de media** (era 46 sobre
LTE, 0,25 en L2 directo) y **los micro tirones desaparecieron**. Eso hizo visible que el
síntoma tenía una causa de código, no de red: ver §2 y `FRENO-INYECTADO.md`.

> 🔴 **El arreglo está verificado en cable, que es justamente el enlace donde el defecto
> casi no se notaba.** La prueba que vale es sobre el enlace donde dolía. **Hay que re-medir
> las tres, con el mismo protocolo**, y el protocolo paso a paso está en
> `FRENO-INYECTADO.md` §7 con la tabla para llenar.

- [x] **Cable post-fix — hecho el 2026-09-10.** 90 s de teleop real: **inyecciones 0**
      (eran 99% de los moves), tráfico hacia el robot **a la mitad** (10.7 → 5.7 cmd/s), y
      los 19 `stop_move` que quedan verificados uno por uno como dead-man legítimo al
      soltar el stick. La cadencia de teleop no cambió: el arreglo no aceleró nada, sacó el
      freno. `FRENO-INYECTADO.md` §6.1.
- [ ] **Re-medir sobre LTE** — es la medición que decide si quedaba algo de jitter puro.
      Si con `stop_move`=0 el tirón persiste, entonces sí es la red y se vuelve a
      `PUERTOS.md` §1, pero ya sin la variable de código encima.
- [ ] **Re-medir sobre Starlink** — misma hora y mismo punto que LTE, o la comparación no
      vale (es el mismo error de aislamiento de variables que ya se cometió en agosto).

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
| **`rt/frontvideostream` por DDS, incluso LEÍDO ADENTRO DEL JETSON** | El tópico existe y nuestro lector **empareja** (suscriptores 1→2), pero **recibe 0 bytes y el callback nunca corre**. No es red ni buffers: subir el socket a 64 MB y tocar `FragmentSize` no cambió nada, y suscribirse no agrega tráfico. Es la deserialización del mensaje; la comunidad reporta lo mismo (`invalid data size`, `std_bad_alloc`). **El camino bueno es RTP multicast en `230.1.1.1:1720`.** `PLAN-VIDEO.md` §3.1 |
| **El cronómetro en cuadro, en ESTE robot** | La pantalla satura la cámara y los dígitos de ms salen un borrón. Y comparar contra el reloj de la notebook dio **-710 ms** y **-1400 ms** — negativos e inconsistentes |
| **Control-to-photon como medida de la latencia de VIDEO** | La idea es sana (los dos extremos son nuestro reloj) pero el marcador no: el robot tarda entre **311 y 1855 ms** en arrancar visiblemente, y un pulso arrancó *después* de que el dead-man ya lo había frenado. El desvío (516 ms) es del orden del número buscado, y **no se promedia**: una demora mecánica es un sesgo con varianza. El video queda exonerado (llega cada 70.5 ms ±4, sin ráfagas ni huecos). Sirve para "lo que el operador siente" (~1076 ms), **no** para latencia de video. `PLAN-VIDEO.md` §9 |
| **`grab()` de OpenCV como forma de "no decodificar"** | En el backend FFmpeg **`grab()` igual decodifica**; `retrieve()` es solo la conversión YUV→BGR. Ahorra conversión y encode de los cuadros descartados (encode 12.91→4.28 fps), pero **no acelera el consumo**: 13.7 fps con y sin |
| **RTMP/TCP para video en vivo sobre un enlace con pérdida** | Cada pérdida cuesta un RTT de retransmisión **y bloquea todo lo que venía detrás**. Medido sobre LTE: pedir 15 fps entregaba 1.90. Con SRT, lo mismo entrega 11.00. **Usar SRT (`PROTO=srt`) en campo, RTMP solo en cable** |
| **Levantar `mediamtx tests/video-bench/mediamtx-test.yml` mientras SRT está en producción** | Su path `srtin` toma el **udp:9000** que producción necesita, y el error (`bind: address already in use`) no dice quién lo tiene. Costó un rato encontrarlo |
| **Subir los fps del MJPEG sobre un enlace con pérdida** | Entrega MENOS, no más: cap 15 → 1.90 fps contra cap 5 → 3.85. Cada pérdida bloquea el stream TCP entero mientras se retransmite. Medido sobre LTE 2026-09-16 |
| **Tocar el encoder H.264 sin fijar B-frames en 0** | `nvv4l2h264enc` los activa según qué otros parámetros toques, y **mediamtx cierra la sesión WebRTC al detectarlos** (`WebRTC doesn't support H264 streams with B-frames`): la vista en vivo se congela. Pasó al ajustar resolución/fps/keyframe para LTE |
| **`cv2.IMREAD_REDUCED_COLOR_2/4/8` para decodificar JPEG más rápido** | OpenCV 4.2.0 en el Jetson del Go2 **ignora el flag**: los tres devuelven 1920x1080 y tardan lo mismo (20.8 ms). No hay atajo por software para el decode; el único camino real es el hardware (`nvjpegdec`) |
| **`CPUQuota` para "que el video no compita con el control"** | Es un techo ABSOLUTO: congela el cgroup aunque la máquina esté ociosa, hasta ~100 ms sin aparecer en ningún profiler. Costó 77 ms por cuadro. Lo correcto es **`CPUWeight`**, que es relativo y solo muerde bajo contención real |
| **`cv2.VideoCapture` sobre `rtsp://`/`rtmp://` de mediamtx para cualquier cosa que se mire en vivo** | Entrega cuadros de **2455 ms**, constantes desde el primero. El mismo stream sale por WebRTC en 200 ms. No lo arregla ninguna opción de FFmpeg, ni el transporte, ni los hilos, ni `writeQueueSize`. Para una vista en vivo usar **WHEP/WebRTC**; RTSP sirve para grabar, no para manejar |
| **`writeQueueSize` bajo en mediamtx (32) para bajar latencia** | No baja nada **y rompe a Frigate**: `reader is too slow, discarding 45 frames` y artefactos en el video. El default (512) se queda |
| **Cronómetro en pantalla filmado por la cámara, leyendo los dígitos** | Los milisegundos salen un borrón y una pantalla blanca satura el sensor. Lo que sí funciona es un **panel que parpadea** medido por brillo promedio, con el reloj servido por nosotros — `latency_clock.py` |
| **fps promedio acumulado como prueba de que un lector le sigue el ritmo a su fuente** | Se come el transitorio de arranque (2.35 s de abrir RTSP + 2.39 s esperando el primer IDR) e **inventa un déficit**: 14.23 fps reales leídos como 12.91. Lo que sirve es la **deriva** entre el PTS del stream y el reloj monotónico, que no necesita sincronizar nada. `reader_bench.py` |
