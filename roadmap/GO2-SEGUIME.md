# Plan · "seguime" en el Go2 — seguir a una persona con la RealSense, todo a bordo

> Parte del ROADMAP (§5.4). Escrito el **2026-10-14**, el día que se montó la RealSense D435i en
> el Go2 (§5.7) y con el Jetson leído por SSH esa tarde. **Nada de esto está construido.**
> Reemplaza lo que decía §5.4 ("alcanza con el tamaño de la caja"): si difieren, gana éste.

---

## 1. Qué es y qué no

**Es:** el operador dice "seguime" (voz o botón), el robot fija a UNA persona y camina detrás
de ella a una distancia fija (~1.5 m), girando para tenerla centrada. Se frena solo si la pierde,
si se le acerca demasiado o si el operador dice cualquier cosa.

**No es (en esta versión):** esquivar obstáculos (solo frena), subir escaleras, re-identificar a
alguien que se fue del cuadro y volvió más tarde, ni seguir en multitudes. Caminar marcha atrás
tampoco: si la persona se acerca, el robot se frena, no retrocede.

## 2. Lo que hay hoy (verificado 2026-10-14)

| Pieza | Estado |
|---|---|
| Jetson del Go2 | **Orin NX**, JetPack 5.1.1 (L4T R35.3.1), CUDA 11.4, **TensorRT 8.5.2 con bindings de Python**. Sin torch |
| RealSense D435i | En el USB 3 del Jetson. Profundidad 848×480 por librealsense 2.50 (ctypes), color por V4L2/GStreamer. Hoy la abre `camera_source.py` para el video (§5.7) |
| YOLO | Corre en **esta PC** (`AI-VL-core`, `yolov8n.pt` por defecto), sobre el video que llega por LTE |
| Comandos | El relay en el Jetson: `move vx vy vyaw` con tope (`MAX_VX` 0.6, `MAX_VYAW` 1.0), **dead-man de 1 s**, orden por `ts` (un `stop_move` más nuevo descarta los `move` viejos), auditoría, tope de 20 pedidos/s |
| Enlace (medido hoy) | LTE con ~40% de pérdida en el aire, ~1 Mbps libre de subida, un congelamiento de 1.3 s (`MEDICIONES.md` 2026-10-14) |
| ⚠️ Trampa del Jetson | `import numpy` solo come 367% de CPU si no se pone `OPENBLAS_NUM_THREADS=1` antes (memoria `jetson-numpy-openblas-spin`) |

## 3. Las decisiones, y por qué

**D1 · Todo el lazo corre en el Jetson, nunca pasa por el server.** Cámara → YOLO → distancia →
velocidad, sin salir del robot. Con el enlace de hoy, un lazo por el server reaccionaría a
imágenes de 100+ ms de antigüedad, y en un congelamiento de 1.3 s el robot seguiría caminando
con la última orden. Además no gasta LTE: por el enlace solo viajan la orden y el estado.
El server queda para lo que le toca: entender "seguime", decir a quién, y mostrar.

**D2 · La cámara es la RealSense, color Y profundidad juntos.** El color para YOLO, la
profundidad para la distancia, del mismo aparato: la caja cae sobre la profundidad que le
corresponde. La cámara front del Go2 no sirve para esto: está en otro lugar, con otro campo de
visión, y cruzarla con la profundidad pediría calibrar las dos entre sí.

**D3 · La distancia se mide, no se adivina por el tamaño de la caja.** Corrige §5.4. El tamaño
de la caja cambia cuando la persona se agacha, gira, o queda tapada a medias; la profundidad no.
Cómo: la mediana de la profundidad en el **tercio central de la caja** (el torso: evita el fondo
que se cuela por los costados y el piso a los pies), descartando ceros.

**D4 · No se alinea la imagen entera.** Alinear profundidad con color cuadro completo es caro en
CPU. Alcanza con llevar a coordenadas de profundidad **solo la región de la caja**, con los
intrínsecos y extrínsecos que da librealsense. Unos cientos de puntos, no 400 mil.

**D5 · YOLO en el Jetson con TensorRT, sin torch.** Exportar a ONNX en esta PC (ultralytics ya
está en `AI-VL-core`), compilar el motor en el Jetson con `trtexec` (FP16), correrlo con los
bindings de Python que ya están. Solo la clase `person`. Modelo chico (`yolov8n` o `yolo11n`).

**D6 · Las velocidades salen por el relay, no por un `SportClient` propio.** Un solo dueño de
los comandos del robot: el relay ya tiene tope de velocidad, dead-man, orden por `ts` y
auditoría, y todo eso tiene que valer también para el seguimiento. El proceso nuevo es un
cliente más del relay, en `127.0.0.1`.

**D7 · El operador siempre gana.** Cualquier `move`, `stop_move` o comando que llegue de la app
corta el seguimiento. El `stop_move` con `ts` del relay ya descarta los `move` viejos; se suma
que el relay le avise al seguidor que suelte.

**D8 · Correa (leash): sin app, no hay seguimiento.** El seguimiento solo sigue mientras la app
mande un "sigo acá" cada pocos segundos (propuesta: 3 s, holgado para los congelamientos de
1.3 s medidos). Si se corta el enlace, el robot se frena. Es la diferencia entre un robot que
sigue a alguien y uno que se va solo.

**D9 · Una sola dueña de la RealSense.** La cámara la puede abrir un solo proceso. El
seguimiento necesita color y profundidad todo el tiempo, así que el proceso de percepción
pasa a ser el dueño, y `camera_source` deja de abrir la cámara: sus opciones `rs_color` y
`rs_depth` toman los cuadros de la percepción. "Una cámara por vez" sigue valiendo para lo que
viaja por el enlace, no para lo que se lee a bordo.

## 4. Las piezas

```
                      Jetson del Go2
 ┌─────────────────────────────────────────────────────────────────┐
 │  robot-perception (NUEVO)                                       │
 │    RealSense: color + profundidad, un solo pipeline, 15 fps     │
 │    → YOLO (TensorRT) → distancia (D3/D4) → tracking → estado    │
 │    → controlador → move/stop ──────────► relay (127.0.0.1)      │
 │    → cuadros para el video ──► camera_source (rs_color/rs_depth)│
 │    → GET /follow (estado, objetivo, distancia) ─► relay ─► app  │
 └─────────────────────────────────────────────────────────────────┘
            ▲ follow_start / follow_stop / keepalive (relay, con token)
            │
 app → backend → executor → relay        ("seguime" por voz o botón)
```

**Dónde vive el código:** propuesta, un repo nuevo `robot-ecosystem/robot-perception`. El
video (`robot-video-pipeline`) es transporte y el relay es mando: la percepción no es ninguna de
las dos. Llega al robot por `git pull`, como todo. *Decisión abierta (§9).*

## 5. Fases, en orden

Cada fase termina en algo que se puede **medir**, y no se pasa a la siguiente sin eso. Las
fases 0-3 no mueven el robot.

### Fase 0 — ¿Le da el Jetson? (medir, sin código nuevo en el robot)
- Exportar `yolov8n` a ONNX en esta PC, compilar el motor en el Jetson con `trtexec --fp16`.
- Medir con el video corriendo como en producción: ms por cuadro de YOLO, CPU y GPU totales.
- Medir RealSense color + profundidad en **un** pipeline de librealsense a 15 fps (con
  `OPENBLAS_NUM_THREADS=1`): CPU.
- **Listo si:** YOLO ≤ 20 ms por cuadro y el Jetson con margen (CPU total < 60%) con todo
  prendido. Si no da, se baja a 320 px de entrada o a 10 fps antes de seguir.

### Fase 1 — La percepción es la dueña de la cámara
- `robot-perception` abre la RealSense (color + profundidad) y publica los últimos cuadros a
  bordo; `camera_source` `rs_color`/`rs_depth` los lee de ahí en vez del aparato.
- **Listo si:** el selector de cámaras de la app anda igual que hoy, con los mismos números de
  §5.7 (0.83 Mbps la profundidad, JPEG 4:2:2, cambio de cámara < 1.5 s), y cerrar el video
  no cierra la cámara.

### Fase 2 — Ver personas y medir a qué distancia están
- YOLO sobre el color, distancia por D3/D4, ángulo respecto al frente con los intrínsecos.
- `GET /follow` en localhost y, por el relay, de solo lectura hacia la app. En la app: cajas y
  distancia dibujadas sobre el video (es JSON chico, no video).
- **Listo si:** contra una cinta métrica a 1, 2 y 3 m, el error es < 5% (la D435 promete ~2% a
  2 m), y con una persona caminando la distancia no salta más de ±10 cm entre cuadros.

### Fase 3 — Fijar a UNA persona
- Tracking por superposición de cajas + continuidad de distancia (tipo ByteTrack, sin red
  neuronal extra). Al arrancar: la persona más cercana y centrada, o la que el operador
  toque en la app.
- Si se tapa menos de 1 s, la retoma; si no, "perdida" y se frena.
- **Listo si:** con dos personas cruzándose delante, el objetivo no cambia en 10 de 10 cruces
  grabados; y una persona que sale del cuadro queda "perdida" en < 1 s.

### Fase 4 — El controlador, en seco
- Calcula `vx` y `vyaw` pero **no los manda**: los muestra en la app ("mandaría…") y los loguea.
- Proporcional sobre la distancia (objetivo 1.5 m, banda muerta ±0.2 m) y sobre el ángulo
  (banda muerta ±5°), con límite de aceleración. `vy` siempre 0. Topes propios por debajo de
  los del relay: `vx` ≤ 0.5 m/s, `vyaw` ≤ 0.8 rad/s. Nunca `vx` negativo.
- **Listo si:** los signos son correctos (persona a la izquierda → gira a la izquierda) y las
  órdenes son suaves (sin saltos de más de 0.1 m/s entre ciclos) caminando delante del robot quieto.

### Fase 5 — El controlador, en vivo, en un pasillo
- Manda por el relay a 10 Hz (la mitad del tope de 20/s del relay: deja lugar al operador).
- Se frena: persona perdida, distancia < 0.8 m, profundidad inválida, correa vencida (D8),
  o cualquier orden del operador (D7).
- **Listo si**, con el robot en el piso y alguien con el control a mano:
  - sigue a paso normal y se frena cuando la persona se frena;
  - se frena en < 1 s al perderla, al cortar la app y al apretar "pará";
  - el `stop_move` del operador gana el 100% de las veces (se ve en la auditoría del relay).

### Fase 6 — En la app y por voz
- Skills `follow_me` / `stop_following` en el executor; el intérprete entiende "seguime",
  "seguilo a él", "pará". Verbos `follow_start` / `follow_stop` / `follow_keepalive` en el
  relay (allowlist, token), que los pasa a `robot-perception`.
- En la app: botón, estado (siguiendo / perdida / frenado y por qué), distancia en vivo.
- `follow_me` entra en `DANGEROUS_SKILLS`: con modo seguro prendido, no arranca.

### Fase 7 — Campo
- Por LTE, al aire libre. Entrada en `MEDICIONES.md` con el enlace anotado: qué pasa con la
  correa cuando el enlace se congela, y el sol sobre la profundidad (la D435 tiene proyector
  IR y estéreo: afuera debería andar, pero hay que verlo).

## 6. Riesgos y lo que no sabemos

- **Campo de visión.** El color de la D435 ve ~69° de ancho: si la persona dobla rápido, sale del
  cuadro. El robot tiene que girar antes de caminar, y la fase 3 decide qué hacer al perderla.
- **Cómo está montada.** El ángulo hacia el frente supone que la cámara mira derecho al frente
  del robot. Si está torcida, hay que medir ese ángulo una vez y restarlo.
- **El Go2 cabecea al caminar.** La imagen se mueve; la mediana del torso debería aguantarlo,
  pero se ve en la fase 5.
- **Carga del Jetson.** Video + YOLO + profundidad juntos: lo dice la fase 0, no se supone.
- **Varias personas iguales** (mismo uniforme): el tracking de la fase 3 no las distingue si se
  superponen mucho tiempo. Fuera de alcance de esta versión.

## 7. Lo que NO hay que hacer

- Cerrar el lazo en el server o por el LTE (D1).
- Usar la cámara front para la distancia (D2), o el tamaño de la caja como distancia (D3).
- Alinear la imagen completa (D4), o instalar torch en el Jetson (D5).
- Un segundo proceso con `SportClient` que mande al robot por fuera del relay (D6).
- Leer la distancia del video coloreado: son 256 colores para 3.7 m y encima JPEG y H.264. Eso
  es para que el operador mire, no para medir.
