# ROADMAP · Bitácora — el registro con fecha

> Parte del ROADMAP, partido el **2026-09-22**. La orientación —cómo leer, los dos robots, el
> estado real de cada capacidad, qué bloquea hoy y las decisiones abiertas— quedó en
> **`../ROADMAP.md`**, que es el archivo que se abre primero. Éste es **el registro histórico**: correcciones a lo que se creía cierto, observaciones de campo y lo ya descartado. Crece para siempre y se lee poco, que es justamente por qué no está en el archivo de cada día.
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
| 4 docs de control del G1 | el mismo roadmap de fases 0-5, tres veces | Consolidado en el ROADMAP. Dos borrados |

**Correcciones del 2026-09-01 al 09-04** (sesión de licencia + ThousandEyes):

| Documento | Decía | Realidad |
|---|---|---|
| `PLAN.md` §5.1 | *"500 MB/día hasta el 25 de agosto"* | **50 GB/día** hasta 2027-09-04 (Partner NFR). El análisis de volumen sigue válido; el presupuesto ya no manda |
| `PLAN.md` §5.2 | *"El trial vence el 25/08"* | Venció, y **dejó la búsqueda muerta 10 días**: con la cuota en 0 el HEC siguió ingiriendo y generó **una violación por día** |
| `PLAN.md` §11 paso 13 | *"si el trial cae a Free se pierde alerting"* | Se pasó a Free y se perdió; **recuperado** con la NFR (`Alerting`, `ScheduledAlerts`) |
| `PLAN.md` §12 | *"¿cuánto consume la otra persona?"* — abierto | **~138 MB/día**, telemetría Cisco (WLC 9800 + CURWB) por HEC |
| `PLAN.md` §2.3 | el contenedor de TE del Jetson es **"(Cisco)"**, implícitamente ajeno | Está en la org **propia** `SILK TECH SRL - 178`, con admin nuestro |
| `PLAN.md` §388 | *"Contenedor ThousandEyes (IOx) en el IR1101: RUNNING"* | El agente `LAB-IR-1101` figura **offline desde ~2026-08-22**, igual que el del Jetson |
| El ROADMAP, 2026-08-31 | *"la app de Splunkbase hace pull, no expone nada"* | **Falso**: la app no hace pull. Los **dos** caminos oficiales son push a HEC |
| `REDEPLOY-EN-EL-ROBOT.md`, 2026-08-27 | `git clone` sin rama | Durante un tiempo la rama por defecto estaba **3-8 commits atrás** de `dev` y el clone dejaba código viejo sin fallar. **Resuelto el 10-09**: `dev` mergeado a la principal, el robot vive en `main` |

**Correcciones del 2026-09-10** (auditoría del ROADMAP contra el código). Las cinco son del
**propio ROADMAP**, que es lo que las hace graves: la fuente de la verdad estaba desfasada.

| Decía | Realidad (2026-09-10) |
|---|---|
| Cabecera: los cuatro docs absorbidos *"borrados"* | Tres sí; `ARQUITECTURA_ROBOT_G1_PROPUESTA.md` sigue trackeado y con **dos referencias vivas**. Pendiente en §7.6 |
| §2: *"70 pasan, 6 xfail — executor 24+2"* | **105 pasan, 8 xfail** — el executor tiene 59+4. Nadie actualizó el número al agregar `test_deadman_contract.py` |
| §7.3: *"Los 4 xfails estrictos"* | Son **8**, y los dos que faltaban son **P0 en el camino del robot en campo** (`RelayTransport`). Un xfail escrito y no registrado en el ROADMAP es un defecto que nadie va a priorizar |
| §7.1: `SAFE_MODE` en `:89`, request en `:1260` | `:90` y `:1256`. Las cuatro de `# noqa: S104` sí estaban exactas |
| §0: *"Aplicado el 10-09 en los tres repos del robot"* | Cierto pero incompleto: `robot-ecosystem`, `robot-splunk-docs` y `unitree_ros2` quedaron fuera. Tabla completa de las 11 ramas en §0 |

**Además:** 14 menciones de `192.168.123.99` siguen repartidas por los docs. Esa IP ya no
existe: esta PC es `192.168.20.99`. `IPS-Y-DONDE-CAMBIARLAS.md` ya lo sabe, el resto no.

Y las fechas de git mienten: 24 de los 50 docs muestran `2026-08-27` porque el commit del
renombre los tocó a todos. No sirven para saber qué está fresco.

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
