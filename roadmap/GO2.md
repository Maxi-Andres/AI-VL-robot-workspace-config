# ROADMAP · Go2 — Track A

> Parte del ROADMAP, partido el **2026-09-22**. La orientación —cómo leer, los dos robots, el
> estado real de cada capacidad, qué bloquea hoy y las decisiones abiertas— quedó en
> **`../ROADMAP.md`**, que es el archivo que se abre primero. Éste es **la lista de trabajo del Go2**, que es el foco hoy.
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

> ✅ **2026-10-07: MJPEG retirado del `/drive` del Go2.** Re-medido sobre LTE Movistar con las
> dos vistas leídas a la vez desde el mismo instante del robot: el H.264 todo-intra llega igual
> en la mediana (94 vs 96 ms) y mucho mejor en la cola (p99 140 vs 301), con 13.7 vs 9.8 fps y
> 0.34 vs 0.55 Mbps, sobre una subida con 1.04 Mbps libres. Botón MJPEG tachado para el Go2 en
> el front (`VideoTransportContext.tsx`, `MJPEG_RETIRED_FOR`); el G1 lo conserva. **La rama UDP
> ya está desplegada** (`h264_udp_leases: 1`, `H264_QP=40` en el `video.env`).
> - [x] **MJPEG fuera del enlace, 2026-10-07 11:50:** el bridge lee el Go2 por WHEP de mediamtx
>       (`GO2_STREAM_URL=https://127.0.0.1:8889/robot/whep`, 720p, en el `.env` local), así que
>       YOLO y el VLM comen el stream del NVR que ya cruza el enlace. Verificado: `clients: 0` en
>       el `:8093` del robot, bridge con `lag_s -0.01`. Costo: las cajas de YOLO ahora van
>       ATRASADAS respecto al intra del `/drive` (WHEP ~200-350 ms contra ~95). Lo arregla el
>       rediseño de YOLO (`AI-VL-ecosystem/docs/PLAN_YOLO_FRAME_PAIRING.md`): YOLO sobre los
>       mismos cuadros que se ven.
> - ✅ Drive intra a **640×360 QP38** (en `video.env` del robot): 84/109/135 ms, 13.7 fps, 0.68 Mbps.
> - ✅ **NVR a 1.3 Mbps CON `latency=900` en `srt-bridge.service`** (era 150; probado a 1000 y
>       recortado a 900 por el operador): descartes de SRT
>       0.0% (antes 10-15% a 1.3, y 20-49% a 0.8 con la subida ocupada). Eso era la grabación
>       de Frigate con bloques y deriva violeta: keyframes de ~22 paquetes que no llegaban
>       enteros. Costo: ~750 ms más en mediamtx (Frigate, WHEP→YOLO/VLM); el `/drive` no lo paga.
>       Ver `MEDICIONES.md` 2026-10-07 12:22.
> - [ ] Confirmar a la vista en Frigate que la grabación ya no se corrompe ni se pone violeta, y
>       que vuelve la vista previa ("No Preview Found").
> - [ ] G1: su receptor sigue en `latency=150` a propósito — por WiFi retransmite todo y no
>       descarta (2026-10-01). Revisarlo sólo si el G1 sale por celular o aparece la misma
>       corrupción en su grabación.
> - ✅ **El flood multicast del `Fa0/0/1` (92-97 Mbps) lo disparamos NOSOTROS**: 89
>       `GetImageSample`/s de `videohub_jpeg_stream` para ~14 cuadros nuevos, cada respuesta un JPEG
>       de 128 KB que el videohub copia a multicast para un lector suyo en PC1. Unicast NO lo
>       arregla (probado, revertido). Arreglo: `REPOLL_MS=50` en `src/videohub_jpeg_stream.cpp`
>       (1.1 llamadas por cuadro, ninguno perdido). ✅ **Desplegado en el Go2 2026-10-07 13:08:
>       bus de 93 a ~30 Mbps (−68%), el lector sigue en 14.26 fps, intra p50 81 ms.** Confirmar
>       el gauge del `Fa0/0/1` en Splunk. [ ] G1: pull + build + restart (mismo binario).
>       Ver `MEDICIONES.md` 2026-10-07 12:40.
> - [ ] `h264_width` en vivo no recalcula el alto (queda 270 → imagen estirada). Bug en
>       `mjpeg_server.py` `set_live_params`; por ahora el tamaño se cambia en `video.env`.
> - [ ] Si el intra "se nota" más lento en pantalla, lo que queda sin medir es el navegador
>       (`VideoDecoder` + canvas). Ver `MEDICIONES.md` 2026-10-07.

> 🟡 **2026-09-23: la rama de manejo por UDP — IMPLEMENTADA, falta probarla en el robot.**
> Sobre Starlink la vista de manejo se cortaba (TCP esperando retransmisiones); ahora puede ir
> por UDP con paridad. Detalle y medición en `robot-splunk-docs/PLAN-VIDEO.md` §6.i.
>
> - [ ] Desplegar `robot/mjpeg_server.py` en el robot y reiniciar el video.
> - [ ] `H264_UDP_PORT=8895` en `unitree_ros2/robot_camera_bridge/.env`, reiniciar el bridge.
> - [ ] `tests/video-bench/drive_probe.py 150` sobre Starlink y comparar con los 10 cortes
>       de TCP del 23-09. Y manejarlo.
> - [ ] Persistir `H264_QP=40` en el `video.env` del robot (hoy dice 36) y dejar pasar
>       `h264_qp` por el `/video-config` del relay, que hoy lo rechaza.
>
> 🟡 **2026-09-23: el control también — `move` por UDP, stop por los dos caminos, dead-man
> 1 s.** Implementado y probado en loopback; falta el robot. `FRENO-INYECTADO.md` §7.2.
>
> - [ ] `git pull && ./build.sh` en `~/robot-command-relay`, `DEADMAN_MS=1000` y
>       `RELAY_UDP_PORT=8097` en su `relay.env`, reiniciar el relay.
> - [ ] `RELAY_UDP_PORT=8097` en `unitree_ros2/robot_executor/.env`, reiniciar el executor.
> - [ ] Ver en `/health` del relay que `udp.accepted` sube mientras se maneja (si queda en 0,
>       el NAT no deja entrar UDP y el executor sigue por HTTP).

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

**Historia, para no repetirla** — dos hipótesis centrales del ROADMAP resultaron falsas:

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
      "30 fps" que el ROADMAP citaba nunca se verificaron; lo medido por multicast es
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

> 🟢 **2026-10-01: migrado y manejado por LTE.** Relay con `go2_command_sender`, todo lo que
> llegó al robot volvió `ok` (stand_up, stand_down, balance_stand, sit, hello, moves).
> Hallazgos y cambios de ese día, **sin commitear al escribir esto**:
> - Los botones del panel que el relay no deja pasar ahora se ven **tachados y deshabilitados**
>   (el executor publica `allowed_skills` por robot en `/transport`, recortado por los verbos
>   que el relay reporta en `/health`).
> - Se agregan al relay del Go2 `stretch`, `scrape`, `heart`, `pose_on`/`pose_off` (pose es
>   un modo: mientras está activo, un `move` inclina el cuerpo en vez de caminar). Falta
>   pull + build en el robot y reiniciar el executor, y probarlos.
> - [ ] **El ack UDP no vuelve por el NAT del IR1101.** Cada tramo de manejo manda 1 move por
>       UDP y el resto por HTTP (`no UDP acks for 0.6s — HTTP for 30s`); los stop UDP sí
>       llegan, `udp.accepted` sube. El G1 (ruta directa, sin NAT) no lo muestra. El robot
>       contesta por `192.168.123.1`, el mismo camino que el HTTP. Falta un `tcpdump` (sudo) de
>       `udp port 8097` en esta PC para ver de qué dirección vuelve el ack — el socket del
>       executor está `connect()`-eado y descarta en silencio un origen distinto.
> - **Decisión del operador (2026-10-01): el relay lleva TODO el set del SDK** — dances, saltos,
>   flips, handstand/upright (on/off), los 6 gaits. La traba es el **Safe** del executor
>   (`DANGEROUS_SKILLS`), que se aplica antes de cualquier transporte; el relay no tiene safe propio.
> - **Velocidades**: el relay recortaba a 0.6 y el pad tenía un solo juego de presets, así que
>   "normal" y "fast" eran lo mismo. Ahora presets por robot (Go2 0.3 / 1.0 / 1.8) y recorte
>   2.0 / 1.0 / 3.0 en executor y relay. **Hay que subir `MAX_*` a mano en el `relay.env` del robot.**
> - **Pose, leído del bus (2026-10-01):** la app entra con `2045` (FreeWalk) + `1028` (Pose, sin
>   parámetro), y sale igual (toggle). En pose el joystick **no** usa la API (ni Move ni Euler):
>   publica en `rt/wirelesscontroller` (y `_unprocessed`), stick derecho, ~10 Hz. **Caminando
>   tampoco**: la app maneja todo por ese tópico, por eso se siente más ágil que nuestro `Move`.
>   Implementado: `joy lx ly rx ry` en el sender, aceptado SOLO tras `pose_on` y cortado por
>   cualquier otro verbo (fuera de pose esos sticks caminan sin pasar por los recortes),
>   republicado a 10 Hz y puesto en cero al vencer el dead-man. Con pose en On, el pad manda
>   `joy` en vez de `move`.
> - [ ] **Walk stair**: no existe en el SDK público (ni en el upstream al 2026-10-01); el SDK
>       de fábrica del robot tiene `SwitchGait(int)` (1011). Sin confirmar en el firmware actual.

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

### 5.5. GPS — funcionando de punta a punta (2026-10-07)

> ✅ **2026-10-07: GPS → Jetson → Splunk → mapa, funcionando y confirmado a la vista.** Cadena:
> módem del IR1101 (`AT+WANT=1`) → NMEA por UDP desde `10.20.0.1` → `go2_nmea_reader.py` en el
> Jetson (`NMEA_SOURCE=10.20.0.1`) → `robot:gps` cada 5 s → dashboard del Go2 (mapa Satélite /
> Calles / Minimal + tarjeta de estado). Lo que queda: dónde va la antena en el robot (el imán no
> pega) y medirlo en movimiento. Historia abajo.
>
> 🟡 **2026-10-06: antena puesta, GPS configurado, todavía SIN datos.** Módulo `P-LTEA7-EAL`
> (Sierra EM7421) en el subslot 0/1 del `IR1101-GO2-01` (SSH desde HQ: `10.1.254.1`). La antena
> va en el SMA **del medio** (ícono de pin; MAIN izquierda, DIV derecha).
> - Lo que se aprendió: **`lte gps enable` y `lte gps mode standalone` no hacen nada hasta un
>   reset del módem** (`hw-module subslot 0/1 reload`, corta el LTE 1-2 min). Antes del reset,
>   `show cellular 0/1/0 gps` dice "acquiring" con la lista de satélites vacía y engaña.
> - **Prueba definitiva de si el motor GPS está vivo:** `lte gps nmea ip udp 10.20.0.1
>   192.168.20.99 10110` y escuchar en esta PC — un GPS prendido emite NMEA cada segundo aunque
>   no tenga fix. Ruta verificada (ping desde Loopback0 y Vlan123 a .20.99 OK). **El NMEA llega
>   (desde 12:43:51)**: GGA/RMC/GSA/VTG/GNS de GPS y Galileo, 1 Hz — el motor está vivo. Pero
>   **ninguna sentencia `GSV`** (cero satélites a la vista), RMC `V`, GSA `1`: a cielo abierto
>   eso es la ANTENA, no la configuración. Primer sospechoso: conector **RP-SMA** (se enrosca
>   pero sin pin central no hace contacto); después cable de 2.90 m o falta de bias (3-5 V en el
>   SMA del medio). Nota: un `ss` con Recv-Q 0 NO prueba que no lleguen paquetes — el lector
>   los consume al instante; eso hizo concluir mal "no llega NMEA" la primera vez.
> - **Dashboard listo antes que los datos:** sección "Posición — GPS del IR1101" en
>   `go2-telemetria-thousandeyes.xml` (mapa + estado). Contrato: `index=go2-robot-data
>   sourcetype=robot:gps`, `lat`/`lon` en GRADOS DECIMALES, `fix` (0/1/2), `sats`, `hdop`,
>   `alt_m`, `speed_kmh`.
> - **Medido 2026-10-06: el SMA GPS del módulo da 0 V** (multímetro probado con una pila, V⎓ 20 V,
>   alfiler en el contacto central, router prendido, antena desenchufada). La antena es ACTIVA
>   (3-5 V, SMA macho con pin — bien) y sin bias su LNA no entrega señal: eso explica motor GPS
>   vivo + cero satélites. Salvedad: algunos módems cortan el bias con la antena abierta.
>   Solución: **bias-T GPS SMA** alimentado a 3.3-5 V (USB) entre antena y módulo; plan B,
>   antena pasiva con cable corto. Pendiente: medir la antena en Ω (abierta = antena rota).
> - ✅ **RESUELTO 2026-10-07: la alimentación de la antena estaba APAGADA en el módem.**
>   `AT+WANT?` → `+WANT: 0`. Se habilitó con `AT+WANT=1` (persiste en el módem) y el SMA del
>   medio pasó a dar tensión (medido). Cómo mandar AT en IOS-XE 26.01.2 — oculto, NO soportado:
>   `configure terminal` → `service internal` → `end`, luego
>   `test cellular 0/1/0 modem-at-command AT+WANT?` (el `?` literal se escribe con **Ctrl+V**
>   antes, si no dispara la ayuda del CLI), y al terminar `no service internal` + `write memory`.
>   Config del router guardada con `lte gps enable`, `lte gps mode standalone` y
>   `lte gps nmea ip udp 10.20.0.1 192.168.20.99 10110`.
>   - ✅ **Primer fix 2026-10-07 13:35:56 UTC**: 14→22 satélites a la vista (GPS, GLONASS,
>     Galileo), SNR hasta 41 dB, HDOP 0.8-0.9, posición −34.636105, −58.399052 (HQ).
>   - **Lector hecho** (`robot-telemetry-agent/gps/go2_nmea_reader.py`, 14 tests, probado contra
>     el NMEA real): solo acepta datagramas del IR1101, valida checksum, convierte ddmm→decimal,
>     suma satélites por sistema, deja de dar posición si el fix tiene más de 30 s, emite
>     `robot:gps` cada 5 s por el mismo pipe del shipper y se cierra si muere el lector DDS.
>   - 🟡 Deploy 2026-10-07: pull + unit reinstalada en el Jetson (21:45), IR1101 apuntado al
>     Jetson con `lte gps nmea ip udp 192.168.123.1 192.168.123.18 10110` + `write memory`.
>     **El IR1101 IGNORA la IP de origen configurada y manda desde su Loopback0 `10.20.0.1`**:
>     el lector descartó todo (`ignored datagram from 10.20.0.1`, n=10000, cero eventos escritos
>     — medido con `/proc/<pid>/io`, wchar quieto). Arreglado en el repo: `NMEA_SOURCE=10.20.0.1`
>     en la unit y como default del lector. ✅ Desplegado 21:59 (`e274bc1`): el lector escribe un
>     evento cada 5 s, el shipper no da errores y el spool está vacío (HEC acepta).
>     ✅ Confirmado a la vista: el punto cae en HQ (Caseros y Av. Colonia), 11/22 satélites.
>     El panel de estado pasó de tabla transpuesta a tarjeta (fix, posición, satélites, HDOP,
>     altura, velocidad, botones a Google Maps/OSM) y el selector de mapa va en la línea del
>     título (confirmado a la vista: una fila, sin hueco que moleste).
>     Tercera opción "Minimal" = el mapa original del panel (`7b91e54`, sin opciones de tiles: el
>     default de Splunk, que sigue al tema oscuro). Va como SEGUNDO `<map>` con `depends`, no como
>     otra URL: apuntar el mapa de Esri a `splunk-tiles-dark` (existe, llega a z7) dibujó vacío
>     incluso fijando el zoom, y un token no puede volver a "sin opción".
>     Un solo token decide (`gps_dark`: un mapa `depends`, el otro `rejects`): con un token por
>     mapa, abrir con `form.gps_base=...` en la URL mostraba los DOS (el `<init>` pisaba al input).
>     El Minimal va con zoom 7 y tope 7 FIJOS: el zoom 15 del original solo andaba porque el mapa
>     estaba visible al cargar y Leaflet lo recortaba; mostrado después por el selector quedaba en
>     15 sobre ningún tile (mapa vacío con el punto).
>   - ✅ Mapa: tiles de Esri (CARTO pide API key, OSM bloquea origen privado), trusted domain
>     `https://server.arcgisonline.com`, zoom máx. 18 (tope de Splunk). Selector Satélite
>     (`World_Imagery`) / Calles (`World_Street_Map`), los dos verificados a z18 en HQ; el gris
>     `Canvas` de Esri se corta en z16. La tabla de estado lee `sats_used`/`sats_view` (el
>     contrato viejo decía `sats`) y muestra "sin datos" en vez de "No results found".
> - **Por qué 0 V (investigado 2026-10-07):** el EM7421 SÍ da bias en el conector GNSS
>   (3.05-3.25 V, 100 mA) y Cisco dice que las antenas activas se alimentan del SMA GPS — pero el
>   módem lo prende/apaga con **`AT+WANT=<0|1>`** (persistente; Sierra pide `=1` para antenas
>   activas). No se encontró si corta el bias con la antena abierta. **IOS-XE 26.01.2 no deja
>   mandar AT al módem:** no existe `test cellular`, `show line` no tiene línea del módem (no hay
>   reverse telnet) y `cellular 0/1/0 lte` solo trae firmware/plmn/profile/sim/sms. Salidas:
>   bias-T externo (recomendado), `service internal` (oculto, sin garantía) o Cisco TAC.
> - Nota de la misma foto: **el SMA DIV del módulo está vacío** — LTE con una sola antena; poner
>   la segunda puede ayudar con los cortes del túnel.
> - [x] Primer fix / primeras sentencias NMEA con satélites (2026-10-07).
> - [x] Lector NMEA en el Jetson — ver arriba.

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

> ✅ **2026-10-07: paneles que no se actualizaban solos.** 8 búsquedas del tablero del Go2 no
> tenían `<refresh>`: los 4 gauges de interfaces del IR1101, los 3 del túnel IPsec y — el peor —
> la de motores, que arma todo el panel de la foto. Sólo cambiaban recargando la página. Ahora
> 60 s (motores 10 s). Igual en las 4 búsquedas base de `wlc9800-curwb.xml`. El G1 ya estaba bien.

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
