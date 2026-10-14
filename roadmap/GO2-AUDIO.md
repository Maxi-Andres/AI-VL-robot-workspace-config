# Plan · que el Go2 escuche y hable — micrófono y parlante en el robot

> Parte del ROADMAP (§5.8). Escrito el **2026-10-14**, con el Jetson y el SDK revisados esa
> tarde. **Nada de esto está construido.** Reemplaza el renglón "Micrófono y parlantes del
> robot" de `PLATAFORMA.md` §7.

---

> **Actualización 2026-10-14 (misma tarde): A0 resuelto y A1 construido.** El Go2 SÍ tiene
> parlante usable por DDS (`audiohub`, modo megáfono) y el mic existe pero solo por WebRTC.
> D1 y D2 quedan resueltas a favor del hardware del robot para la SALIDA; para la entrada se
> usa el mic del navegador por ahora. Detalle y números en `GO2.md` §5.8.

## 1. Qué se quiere

- **Que el robot hable:** las respuestas de la app (el VLM, confirmaciones, "te perdí")
  salen por un parlante **en el robot**, no en el navegador del operador.
- **Que el robot escuche:** hablarle al robot donde está ("seguime", "pará", "¿qué ves?")
  sin tener la app abierta en la mano.

## 2. Lo que hay hoy (verificado 2026-10-14)

| Pieza | Estado |
|---|---|
| STT | **Existe**, en el server: Whisper local (`faster-whisper`, `AI-VL-core/src/asr_common.py`) |
| TTS | **Existe**, en el server: Piper, devuelve un WAV (`AI-VL-core/service.py` `/tts`) |
| Intérprete frase → skill | **Existe** (`AI-VL-core`, executor) |
| Asistente de voz | **Existe, pero en el navegador**: graba con el mic de la PC/teléfono del operador y habla por sus parlantes |
| Audio del **Jetson** | **No tiene mic ni parlante.** `aplay -l`: solo HDMI; `arecord -l`: solo las líneas internas del Orin (APE), sin nada conectado. USB: solo la RealSense (que no tiene mic) |
| Audio del **Go2** por el SDK | `unitree_sdk2` para el Go2 solo trae **VUI: volumen y brillo de luces** (`go2/vui/vui_client.hpp`). Nada para reproducir audio ni leer el mic — el G1 sí lo tiene (`g1/audio`: TTS, reproducir, ASR) |
| Audio del Go2 por otro lado | La app oficial de Unitree hace "megáfono" y reproduce audio, por WebRTC. **No verificado** si nuestro Go2 tiene parlante/mic accesibles desde el Jetson; el censo de tópicos (`CENSO-GO2.md`) no lista nada de audio, y `ros2 topic list` en el Jetson se cae (core dump), así que no se pudo mirar en vivo |

## 3. Las decisiones, y por qué

**D1 · Primero averiguar si el Go2 ya tiene parlante y mic usables; si no, uno USB en el
Jetson.** Lo del Go2 sale gratis pero depende de una API no documentada de Unitree (la de la
app, por WebRTC o por tópicos internos). Lo USB es estándar (ALSA), lo controlamos entero, y
cuesta poco.

**D2 · Si es USB: un speakerphone de conferencia, no un mic y un parlante sueltos.** Tipo Jabra
Speak o Anker PowerConf: traen **cancelación de eco por hardware** (el robot no se escucha a sí
mismo hablando), varios micrófonos y un parlante decente, todo por un USB. El ruido del robot
(ventiladores, patas) es el enemigo del mic; el eco es el enemigo de escuchar mientras habla.
Hay que ver dónde se monta y que aguante el movimiento.

**D3 · Hablar: el TTS se genera en el server y el robot solo reproduce.** Piper ya existe. Una
frase de 3 s en Opus son ~10 KB: se manda al relay (autenticado, como todo) y el Jetson la
reproduce. Nada de TTS en el Jetson por ahora.

**D4 · Escuchar: palabra de activación y detección de voz EN EL ROBOT; el texto en el server.**
Mandar el micrófono abierto todo el tiempo por el LTE no tiene sentido. En el Jetson corre un
detector de palabra clave liviano (tipo openWakeWord) + detección de voz; solo cuando alguien
le habla, el robot manda **esa frase** (Opus, unos KB) al server, que la pasa por el Whisper
que ya existe y por el intérprete. Si el enlace resulta muy malo, el Whisper puede bajar al
Jetson más adelante (Orin NX con CUDA lo corre), pero eso es fase posterior.

**D5 · "Pará" se reconoce también a bordo, sin el enlace.** Es la palabra que no puede
esperar al LTE: el detector a bordo la reconoce y frena el robot por el relay directamente.
**Nunca es el único freno** (la voz puede fallar): es uno más, como el botón y el dead-man.

**D6 · Mientras el robot habla, no escucha** (salvo "pará"). Al principio, medio-dúplex: más
simple y sin eco, aunque el speakerphone cancele. Se abre a dúplex completo si hace falta.

## 4. Fases, en orden

### Fase A0 — ¿Qué tiene el Go2? (sin comprar nada)
- Buscar el servicio de audio del Go2: los tópicos internos que usa la app (los proyectos de la
  comunidad que hablan WebRTC con el Go2 documentan un "audiohub"), escuchando el bus DDS desde
  el Jetson con el lector nativo que ya usa la telemetría (no `ros2`, que se cae).
- Ver si hay parlante (que suene algo) y si hay mic (que llegue audio).
- **Listo si:** respuesta clara, con evidencia: "sí, por tal API" o "no / no accesible". Si es
  "no", se compra el speakerphone (D2) ese mismo día — es lo que más demora.

### Fase A1 — El robot habla
- Verbo `say` en el relay (allowlist, token): recibe un audio corto y lo reproduce en el robot.
  Tope de tamaño y de duración; uno a la vez, el nuevo corta al viejo.
- En la app: un interruptor "hablar por el robot" en el asistente de voz; las respuestas del
  VLM y los avisos van al robot en vez de (o además de) el navegador.
- **Listo si:** se entiende a 3 m con el robot parado, y la latencia de "aprieto enviar" a
  "suena en el robot" se mide por LTE y queda en `MEDICIONES.md`.

### Fase A2 — El robot escucha (apretando un botón)
- Primero sin palabra clave: un botón en la app abre el mic **del robot** unos segundos, el robot
  manda la frase, el server la transcribe e interpreta. Aísla el problema del mic (ruido,
  distancia, eco) del problema de la palabra clave.
- **Listo si:** 9 de 10 órdenes cortas entendidas a 2 m con el robot parado, y 7 de 10 con el
  robot caminando (el ruido de las patas es lo que hay que medir).

### Fase A3 — Palabra de activación y "pará" a bordo
- Detector a bordo de la palabra de activación (nombre a elegir) y de "pará". Con la palabra,
  hace lo de A2 solo; con "pará", frena por el relay sin esperar al server.
- **Listo si:** "pará" frena en < 1 s con el enlace cortado; y menos de 1 activación falsa por
  hora con gente hablando alrededor (medido, no supuesto).

### Fase A4 — Conversación
- El asistente de voz completo desde el robot: escucha → VLM → responde por el parlante del
  robot, con el medio-dúplex de D6. Se une con "seguime" (fase 6 de `GO2-SEGUIME.md`).

## 5. Riesgos

- **Ruido propio del robot.** Ventiladores y patas; el Go2 caminando es ruidoso. A2 lo mide.
- **Volumen afuera.** Un speakerphone de escritorio puede no alcanzar en la calle.
- **Montaje.** Vibración, golpes, cables: el speakerphone tiene que ir firme y no tapar la
  RealSense ni la antena.
- **Consumo LTE.** Bajo si se respeta D4 (solo frases): una frase son unos KB. Con mic abierto
  continuo serían ~10 MB/h en Opus: tolerable, pero innecesario.
- **CPU del Jetson.** Palabra clave + detección de voz son livianas, pero se suman al video y a
  la percepción de "seguime". Se mide junto con la fase 0 de `GO2-SEGUIME.md`.
