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
