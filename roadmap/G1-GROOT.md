# Plan · GR00T en el G1 — manipulación aprendida (fase 8 de §6.2)

> Parte del ROADMAP. Escrito el **2026-10-13** con investigación web del mismo día (fuentes al
> final, cada número con su link) y con el robot leído por DDS esa tarde. Reemplaza como plan a
> lo que decían sobre GR00T `AI-VL-ecosystem/docs/ARQUITECTURA_ROBOT_G1_PROPUESTA.md` y
> `G1_FASES_Y_CREAR_SKILLS.md` (agosto): esos quedan como contexto. Si difieren, gana éste.
>
> GR00T se mueve rápido. Lo que dice "verificado 2026-10-13" puede cambiar: re-chequear la
> versión y los requisitos antes de cada compra o cada fine-tune.

---

## 1. Qué es cada cosa (para no mezclar)

| Pieza | Qué hace | Dónde corre |
|---|---|---|
| **VLM de la app** (Qwen3-VL-4B-Instruct Q4_K_M en llama-server propio, `:8081`, `AI-VL-core`; antes `qwen3-vl:4b` en Ollama) | Entiende la escena y la frase, decide **qué** hacer ("agarrá la taza") y verifica si salió | esta PC |
| **GR00T N1.7** (VLA, 3B) | Recibe imagen + estado del robot + una instrucción corta y devuelve **cómo** mover brazos y dedos (trozos de acción) | un servidor con GPU (no PC2, ver §3) |
| **PC1** (cerrado) | Caminar y equilibrar. **Sigue mandando las piernas** en el camino A | el robot |
| **PC2** (Orin NX 16 GB, JetPack 5.1.1) | Cámara + cliente de la política: lee estado, le pide acciones al servidor, las escribe en `rt/arm_sdk` y en el servicio de las manos (Inspire, ver §2) | el robot |

La VLM y GR00T no compiten: la VLM es el capataz que dice "ahora agarrá la taza", GR00T es la
mano que sabe agarrarla. GR00T trae su propia VLM adentro (Cosmos-Reason2-2B), pero solo para
condicionar el movimiento: no reemplaza a la nuestra.

## 2. Lo que tiene NUESTRO robot (verificado 2026-10-13 por DDS desde PC2)

- 29 DoF, cintura de 3 ejes (bloqueada = roll/pitch inactivos, torque 0).
- **⚠️ 2026-10-15: son BrainCo (tipo Revo 2), ni Dex3-1 ni Inspire** — confirmado por Modbus
  (`G1-CONTROL-ARTICULAR.md` J4). Unitree publica datasets `G1_Brainco_*` y `xr_teleoperate`
  tiene `--ee brainco`: esa es la variante a usar. Lo que sigue en este punto quedó viejo.
- **Manos: Inspire de CINCO dedos, no Dex3-1.** ⚠️ **Corregido el 2026-10-14**: el usuario lo
  vio en el robot. Antes decía "Dex3-1 en las dos", deducido de que el robot lista
  `/dex3/left|right/state` con publicador; ese tópico existe, pero no dice qué mano tiene
  puesta (qué lo publica, sin verificar). La Inspire tiene 6 motores por mano (no 7), se maneja
  por su **propio servicio** (no por el firmware; no se vio ninguno corriendo) y hay dos
  modelos: **DFQ** (RS485 por USB) y **FTP** (Ethernet, IPs `192.168.123.210/211`). El modelo
  3D de la app usa DFQ, el del proyecto LuckyEngine; **falta confirmar cuál es** (con el robot
  prendido: `ping 192.168.123.210` desde PC2 → FTP; un `/dev/ttyUSB*` de la mano → DFQ).
  **Qué cambia en este plan:** todo lo que dice Dex3 abajo (datasets de Unitree "G1_Dex3",
  `--ee dex3`, 28-D = 14 brazos + 7 + 7) hay que pasarlo a la variante Inspire: Unitree publica
  también datasets G1 con Inspire, y `xr_teleoperate` tiene su opción de mano Inspire. La
  dimensión pasa a 14 + 6 + 6 = 26. Sin revisar todavía en detalle.
- `rt/arm_sdk`, `rt/hand_sdk`, `rt/user_lowcmd`, `rt/lowcmd`, odometría y nube de puntos del
  SLAM de Unitree (sin publicar mientras no corre el mapeo).
- Cámara de cabeza: **RealSense D435i, monocular** (los datasets de Unitree usan cabeza estéreo
  + dos cámaras de muñeca; nosotros no tenemos las de muñeca).
- PC2: Jetson **Orin NX 16 GB, JetPack 5.1.1 (L4T R35.3.1)**, 1.8 TB libres.
- Esta PC: **RTX 5060 8 GB**. Minisforum **G1 Pro** (así lo dice la placa), **Ubuntu 26.04.1**,
  **28 GiB de RAM utilizables** (verificado 2026-10-21). ROS2 Humble existe **solo dentro del
  contenedor** (Ubuntu 22.04.5), no en la PC: el plan del 2026-10-21 decía "22.04.5" y "32 GiB
  utilizables" por eso (`G1.md` §6.7 punto 1).
- 🔴 **Camina echado para atrás** desde la última calibración (`G1.md` §6.4). Hay que
  arreglarlo antes de grabar datos.

## 3. Las dos decisiones que definen el plan

### 3.1. Camino A (Unitree, PC1 camina) vs. camino B (NVIDIA SONIC, cuerpo completo)

| | **A — `rt/arm_sdk` + Dex3** | **B — SONIC / WBC de NVIDIA** |
|---|---|---|
| Piernas | **PC1, como hoy** | Las toma una política RL propia por `rt/lowcmd`; libera el servicio de control de Unitree. **El L2+B (amortiguar) del control deja de andar** mientras corre |
| Qué controla GR00T | 14 articulaciones de brazos + 7+7 de dedos | Cuerpo entero (token de movimiento de 64 + manos) |
| Teleop | `xr_teleoperate --motion` (Quest 3, PICO 4 Ultra, Vision Pro) | PICO 4 + 2 trackers de tobillo (XRoboToolkit). Sin Vision Pro |
| PC2 | Sirve tal cual (JetPack 5.1.1) | **Reflashear a JetPack 6.2** (sacar el NVMe), TensorRT exacto o "comportamiento peligroso" |
| Riesgos | El de brazos (pesos, velocidades) | **Recalentamiento documentado**: tobillo 90 °C en 5-10 min aun quieto, cintura 126 °C una vez (issues abiertos) |
| Hace loco-manipulación (caminar mientras agarra) | No: PC1 camina, la política no lo maneja. Caminar → frenar → agarrar | Sí |

**Recomendación: A.** Toda nuestra arquitectura (relay, executor, Safe, dead-man) asume que
PC1 equilibra, el robot ya se cae para atrás con el controlador de fábrica, y B suma un
reflasheo y un riesgo térmico documentado. B queda como fase 9 (opcional), y nada de A se
tira si después se va a B: los datos se pueden volver a grabar, el servidor y el cliente son
los mismos.

GR00T en A va con el tag **`NEW_EMBODIMENT`** (el `UNITREE_G1_SONIC` es solo para B; el
`REAL_G1` del modelo base sin fine-tune da "solo pequeños movimientos de equilibrio", issue
#650). Es como lo hace el curso oficial de NVIDIA con G1 + Dex3-1 + D435.

### 3.2. Cómputo — la RTX 5060 de 8 GB no alcanza

| Uso | Qué pide (verificado 2026-10-13) | Qué tenemos |
|---|---|---|
| Inferencia | ≥16 GB VRAM. Latencias TensorRT: H100 28 ms · L40 38 ms · AGX Thor 80 ms · AGX Orin 64 GB 151 ms. <10 Hz = "solo tareas lentas" | 5060 8 GB: bajo el mínimo + bugs abiertos en Blackwell de consumo (#590, #309). Orin NX: **no**, N1.7 pide JetPack 7.2 |
| Fine-tune | 1 GPU ≥40 GB (pico ~35 GB). N1.7 **no tiene LoRA** | nada |

**Recomendación:** fine-tune en la nube (1× H100/A100 80 GB por horas) y, para inferencia, un
servidor con **24-32 GB** (RTX 4090/5090, L40S o RTX 6000 Ada) en la VLAN 20, cerca de Splunk.
La alternativa "oficial" es una **Jetson AGX Thor** (la usa el curso de NVIDIA, 80 ms), que
además podría ir en mochila. Decisión de compra del usuario — §8.

## 4. El plan, paso a paso

Cada paso tiene **cómo se sabe que está hecho**. No se pasa al siguiente sin eso.

### Paso 0 — El robot sano, y nuestro código moviendo brazos y dedos (sin gastar nada)

> **2026-10-13: se hace con una interfaz, `G1-CONTROL-ARTICULAR.md`.** Sus pasos J2 (codo por
> `arm_sdk`) y J4 (las manos Inspire) cubren los dos puntos de código de acá, y J1/J5 el diagnóstico de la
> inclinación. Ese plan va primero, mientras se consigue la GPU.

- [ ] Arreglar la inclinación hacia atrás (`G1.md` §6.4). Grabar demos con el robot torcido
      ensucia el dataset.
- [ ] Manos Inspire (no Dex3, ver §2): identificar el modelo (DFQ/FTP), instalar su servicio
      en PC2, primero solo leer el estado, después abrir/cerrar con fuerza baja. (Antes decía
      correr `g1_dex3_example`: es para la otra mano.)
- [ ] `rt/arm_sdk` desde PC2: un ejemplo propio a partir de `g1_arm7_sdk_dds_example.cpp`
      que suba el peso de 0 a 1 en 2 s, mueva un codo 20° y baje el peso. Con el robot parado
      en modo Regular (500), operador con el control en la mano.
- [ ] Ver qué pasa con las acciones de brazo del relay mientras `arm_sdk` está tomado (error
      7400): el relay tiene que **negarlas** con un mensaje claro, no encolarlas.
- **Hecho cuando:** un brazo y una mano se mueven por código nuestro con PC1 equilibrando,
  y la telemetría no muestra temperaturas raras (el tablero ya las tiene).

### Paso 1 — La GPU (indispensable; el casco NO va acá)

- [ ] GPU de inferencia (§3.2), o arrancar alquilando. Sin ella no se prueba ni el modelo ya
      entrenado (1A) ni la simulación (1B).

  > **Opciones de compra (investigado 2026-10-16, precios de oct. 2026 en EE. UU., en suba;
  > también en la presentación, diapositiva 6).** NVIDIA pide 16 GB para correr N1.7 y 40 GB
  > para entrenarlo (receta normal ~35 GB; visión y lenguaje, 80 GB). Velocidad oficial con
  > TensorRT, mínimo recomendado 10 Hz:
  >
  > | Opción | Memoria | Corre | Entrena | Precio aprox. |
  > |---|---|---|---|---|
  > | **Alquilar H100** (Lambda, RunPod, Vast) | 80 GB | ~36 Hz | todo | USD 2.6-4.2/h; un ajuste de 10K pasos ≈ USD 10-17 (estimación de la comunidad: 3-4 h) |
  > | DGX Spark (GB10) | 128 GB unificada | 10.1 Hz | entra, pero lento | ~USD 4.700 |
  > | RTX 5090 | 32 GB | ~32 Hz | solo ajustes chicos (la receta normal no entra) | ~USD 5.000, escasa |
  > | RTX 4090 usada | 24 GB | ~23 Hz | LoRA (N1.5) | ~USD 2.500-3.000 |
  > | RTX 6000 Ada / L40S | 48 GB | 26 Hz (L40) | receta normal | ~USD 7.000-8.500 |
  > | **RTX PRO 6000 Blackwell** | 96 GB | ~36 Hz | todo | ~USD 16.000 (era 8.565 al lanzarse) |
  > | **Jetson AGX Thor** (en el robot) | 128 GB | 10.7-12.4 Hz | no | ~USD 5.500 (subió de 3.499 en julio) |
  > | Orin NX 16 GB (la de PC2) | 16 GB | ~2-3 Hz **estimado**, sin pruebas publicadas | no | ya está: sirve para ACT |
  >
  > Recomendación: alquilar para entrenar y usar ACT con lo que ya hay; comprar recién si la
  > puerta 1C lo justifica (PRO 6000 para entrenar seguido, Thor para llevarlo en el robot).
  > Argentina: courier hasta USD 3.000 por envío; lo caro va por importación formal con
  > despachante (fuentes secundarias). Fuentes: github.com/NVIDIA/Isaac-GR00T (README y
  > `getting_started/hardware_recommendation.md`), nvidia-isaac-gr00t.mintlify.app/deployment/tensorrt,
  > tomshardware (PRO 6000, DGX Station), videocardz y cnx-software (precio de Thor),
  > huggingface cloudwalk-research/GR00T-N1.6-G1-PnPAppleToPlate (horas de ajuste).
- [ ] Opcional pero recomendado a mediano plazo: **dos cámaras de muñeca USB**. Todos los
      datasets G1 serios las tienen; para agarrar, la cámara de cabeza sola pierde el objeto
      detrás de la mano.

> **Decidido con el usuario 2026-10-13: primero se intenta SIN casco** (1A → 1B → 1C). El
> casco se compra solo si la puerta 1C lo pide. Lo que se sabe de antemano, para no
> ilusionarse: GR00T base sin fine-tune no hace nada útil en un G1 (#650), y la simulación
> sola no transfiere bien con visión (#583: el checkpoint G1 de sim "retuerce los brazos" en
> el robot real). NVIDIA y Unitree usan la sim como **complemento** de datos reales.

### Paso 1A — Probar el modelo YA entrenado, tal cual

`nvidia/GR00T-N1.7-ApplePnP-V1`: entrenado en un **G1 real con nuestro mismo hardware**
(Dex3-1 + D435 en la cabeza), 402 demos, tarea "manzana al plato". Es lo más cerca de "un
modelo que ya sabe" que existe.

- [ ] Servirlo con `run_gr00t_server.py` en la GPU y leer su `modality.json`: qué estado y qué
      acciones espera, en qué orden y unidades.
- [ ] **Sus acciones incluyen piernas** (lo entrenaron con el control de piernas de NVIDIA, no
      con PC1): el cliente usa SOLO brazos + manos y descarta las columnas de piernas/nav/altura.
      Robot parado en Regular, PC1 equilibrando.
- [ ] Primero **en seco**: alimentarlo con cuadros y estado reales y mirar las acciones que
      propone, sin mandarlas (`--send_real_robot=false` o equivalente). Recién si son sensatas,
      al robot con velocidad reducida.
- [ ] Armar su escena lo más parecida posible a la de ellos: manzana, plato, mesa a la altura de
      su dataset (`nvidia/GR00T-N1.7-AppleToPlate`, CC-BY-4.0: mirar sus videos).
- [ ] 20 intentos, anotar éxitos.
- **Hecho cuando:** hay un número. Expectativa honesta: bajo (otra mesa, otra luz, otra
  posición de cámara). Pero si se acerca, cambia todo el plan: con pocas demos propias de
  ajuste alcanzaría.

### Paso 1B — Simulación con demos generadas por código, sin casco

- [ ] `unitree_sim_isaaclab` con G1-29 + Dex3 (tareas PickPlace-Cylinder, PickPlace-RedBlock,
      Stack-RgyBlock). Pide Isaac Sim 5.x en RTX 50 y probado solo en 3080/3090/4090 — la 5060 de
      8 GB casi seguro no alcanza (**a verificar** el mínimo de VRAM de Isaac Sim); va en la GPU
      del paso 1. **Nunca en el segmento del robot**: habla los mismos tópicos DDS.
- [ ] Generar demos **sin humano**: un agarre programado (pose del objeto que da la sim →
      cinemática inversa del brazo → acercar, cerrar la Dex3, levantar, llevar, soltar), con
      posiciones de objeto al azar, cientos de episodios. Alternativa: **Isaac Lab Mimic**, que
      multiplica unas pocas demos en cientos (pero esas pocas salen de algún lado: el agarre
      programado mismo sirve).
- [ ] Aleatorizar luz, texturas y posición de cámara (`--modify_light` / `--modify_camera` del
      repo; las funciones las escribe uno).
- [ ] Mismo formato que las demos reales (`--replay` y `--generate_data` del repo graban en el
      formato de `xr_teleoperate`) → misma conversión del paso 3 → entrenar ACT (paso 4) y
      GR00T (paso 5) **en sim**, y medir éxito **en sim**.
- [ ] Recién después: el modelo entrenado en sim, al robot real, con un cilindro/bloque igual
      al de la sim. 20 intentos.
- **Hecho cuando:** hay número en sim y número en real. Lo valioso aunque el real dé bajo:
  la cañería entera (datos → entrenamiento → servidor → cliente en PC2) queda probada sin
  haber comprado el casco.

### Paso 1C — La puerta: ¿hace falta el casco?

- Si 1A o 1B dan un éxito real razonable → ajustar con **pocas** demos reales. Para pocas
  alcanzan los caminos sin casco:
  - **Mover los brazos con la mano** mientras se graba (`arm_sdk` con rigidez baja). Bueno
    para brazos; los dedos van aparte y queda torpe.
  - **Cámara común siguiendo las manos** (MediaPipe → retargeting). Barato, calidad baja.
  - Joystick/teclado: demos lentas, y el modelo aprende esa lentitud. Última opción.
- Si los dos dan casi cero en real → **comprar el casco** (§8, decisión 2) y seguir por el
  paso 2. Es lo que coincide en todo lo publicado para tareas reales en un entorno propio.
- En los dos casos los datos de sim **se quedan**: se mezclan con los reales en el paso 5.

### Paso 2 — Teleoperación con `xr_teleoperate` (si la puerta 1C lo pide)

- [ ] `teleimager` en PC2 con la D435i (la soporta: extra `[realsense]`).
- [ ] `xr_teleoperate --arm G1_29 --ee dex3 --motion`. **Dónde corre el programa es lo
      primero a resolver**: publica DDS al robot, y por WiFi el DDS **no cruza** (§6.5). O
      corre en PC2 (Python 3.10 en conda, aarch64 — a verificar) y el casco se conecta a PC2 por
      la WiFi de robots, o se graba con el robot **cableado** a la red del robot y una PC en ese
      segmento. Para una mesa de grabación, el cable es lo razonable.
- [ ] Ojo con lo que hace `--motion`: cintura quieta (solo brazos 15-28), robot en Regular
      (R1+X), **Running no está soportado**, se camina con los joysticks, las dos palancas
      apretadas = parada suave a amortiguado.
- **Hecho cuando:** el operador hace 10 agarres seguidos con el casco sin que el robot se
  desequilibre, y sabemos la latencia del casco al brazo.

### Paso 3 — Una sola tarea, chica y fija, y los primeros 50 episodios

- [ ] Elegir **una** tarea angosta: robot parado frente a una mesa fija, "agarrá la taza y
      ponela en la caja". Misma mesa, misma luz, posiciones de la taza variadas.
- [ ] `--record` → 50 episodios de ~20-30 s. Calcular ~1-1.5 h de grabación con los reseteos.
- [ ] Convertir con `unitree_IL_lerobot` (`convert_unitree_json_to_lerobot.py --robot_type
      Unitree_G1_Dex3`) y **revisar** con `replay_robot.py` / `eval_g1_dataset.py
      --send_real_robot=false` antes de entrenar nada.
- **Hecho cuando:** el replay de un episodio en el robot reproduce el movimiento grabado.

### Paso 4 — Línea base barata: ACT en esta PC

ACT es chico (entrena en la 5060). Sirve para probar **toda la cañería** —datos, entrenamiento,
deploy con `eval_g1.py --motion`— con hardware que ya tenemos, antes de gastar en GR00T.

- [ ] `lerobot_train.py --policy.type=act` sobre los 50 episodios.
- [ ] Deploy en el robot, **20 intentos** cronometrados, anotar éxitos.
- **Hecho cuando:** hay un número de éxito medido (aunque sea 30 %: prueba la cañería).

### Paso 5 — GR00T N1.7

- [ ] Subir a **~200 episodios** de la misma tarea (los docs: ~100 mínimo, 200+ para estable;
      NVIDIA usó 200 en su curso G1 y sacó 68 %).
- [ ] Llevar el dataset al formato de GR00T: **LeRobot v2 + `meta/modality.json`**
      (estado/acción 28-D = 14 brazos + 7+7 Dex3, video `ego_view` 640×480 H.264, no AV1).
- [ ] Fine-tune `nvidia/GR00T-N1.7-3B`, `--embodiment-tag NEW_EMBODIMENT`, 1× GPU 80 GB,
      ~10k pasos. Separar episodios de validación.
- [ ] **No creerle al MSE**: el issue #414 tuvo buen MSE offline con 600 episodios de G1 y casi
      cero éxito real. Lo único que vale es el robot.
- [ ] Servir con `run_gr00t_server.py` (ZMQ :5555, con `api_token`) en el servidor GPU, con
      TensorRT. Cliente en PC2: lee cámara y estado, pide un trozo de acciones, ejecuta 8-16
      pasos a 30 Hz mientras pide el siguiente, y escribe en `rt/arm_sdk` + `rt/dex3/*`.
- [ ] Los mismos 20 intentos del paso 4.
- **Hecho cuando:** GR00T le gana a ACT en la misma tarea, medido.

### Paso 6 — Conectarlo a la app: voz → VLM → GR00T, en una pestaña nueva

**Pedido del usuario 2026-10-13:** el "Robot command (interpreter)" de `/` quedó flojo —mapea
una frase a UN comando fijo ("sentate" → se sienta)— y el "VLM (on demand)" solo describe la
imagen. Lo que se quiere es **una pestaña nueva en el header, solo para esto**: video del
robot + un chat, hablándole por voz o escribiendo, y **viendo qué va pensando y qué va
haciendo**. Es la cara de la fase 6 (planificador) y se puede arrancar **antes** de GR00T, con
los skills que ya existen.

- [ ] Ruta nueva (p. ej. `/agent`) en `App.tsx` + entrada en `Header.tsx`. Layout: video a la
      izquierda (el mismo componente de `/`, con el mismo selector de transporte), chat a la
      derecha.
- [ ] Entrada: texto o voz (STT de iacore, ya existe). Salida: texto + TTS (Kokoro, voz Alex desde 2026-10-19, ya existe).
- [ ] **Traza visible, en vivo**, como pasos del chat: qué entendió → el plan (lista de
      subtareas) → cada skill que ejecuta y su resultado → qué vio la VLM para verificar. Por
      streaming (SSE o el WS existente), no al final.
- [ ] El cerebro detrás: un LLM con herramientas (los skills del catálogo + "mirar la cámara"
      con la VLM + más adelante `manipulate`) que reemplaza al intérprete de un solo skill.
      Siempre detrás de Safe/STOP: el botón de STOP vive también en esta pestaña.
- [ ] Skill nuevo `manipulate(instruction)` en el catálogo de `AI-VL-core` (`command_common.py`).
- [ ] El executor arranca el cliente de política con la instrucción, con tiempo máximo.
- [ ] **Arbitraje**: mientras corre, el relay rechaza locomoción y acciones de brazo; al
      terminar, el peso de `arm_sdk` baja a 0 en 2 s y PC1 recupera los brazos.
- [ ] La VLM mira el cuadro final y responde "¿la taza está en la caja?" → feedback hablado.
- **Hecho cuando:** "agarrá la taza y ponela en la caja" por voz termina con el robot diciendo
  si lo logró, y es cierto.

### Paso 7 — Escalar

- Más tareas con la misma política (GR00T es multitarea por instrucción): ~100-200 episodios
  por tarea nueva.
- Cámaras de muñeca, si no se hizo en el paso 1.
- `unitree_sim_isaaclab` para repetir episodios con otra luz/cámara (tiene tareas G1 + Dex3;
  pide Isaac Sim 5.x para RTX 50, y **nunca en el segmento del robot**: habla los mismos
  tópicos DDS).
- Caminar → agarrar → caminar: lo arma el planificador (fase 6) encadenando locomoción de PC1
  y `manipulate`. Caminar *mientras* agarra es el camino B (fase 9).

## 5. Seguridad — no negociable

- Rampa de peso en `arm_sdk` al entrar y salir (2 s), recorte de velocidad, límites
  articulares.
- Dead-man: si el cliente deja de recibir acciones del servidor (red, crash), mantiene la
  última posición y baja el peso. Mismo criterio que el dead-man del relay.
- Siempre un operador con el control físico. Las dos palancas = amortiguado.
- Temperaturas: el tablero ya muestra los 29 motores; poner alerta en Splunk antes del paso 2.
- Primeras pruebas de cada política nueva con la tarea a velocidad reducida.

## 6. Riesgos

- **Datos**: la cifra que más pesa. NVIDIA usó de 150 a miles de episodios; con 50 no se espera
  que GR00T ande, por eso ACT primero.
- **Sin casco puede no alcanzar**: modelo ya entrenado y sim son apuestas baratas, no seguras
  (#650, #583). La puerta 1C existe para no seguir empujando si dan cero.
- **Sin cámaras de muñeca** el éxito puede quedar bajo en agarres finos.
- **El MSE miente** (#414) y **la versión importa**: el checkpoint oficial de G1 en sim dio 0-1 %
  en el `main` actual contra 58 % esperado (#574/#590). Fijar el commit de Isaac-GR00T con el
  que se entrena y servir con ese mismo.
- **Orin da distinto que una workstation** (#712: 2.5× el error con el mismo modelo): no mover
  la inferencia a una Jetson sin re-medir.
- **WiFi**: el cliente en PC2 habla ZMQ con el servidor por la WiFi de robots. Medir latencia y
  pérdida antes del paso 5 (el agente TE de PC2 ya lo mide hacia HQ).

## 7. Licencias

Código Apache 2.0. Pesos: **NVIDIA Open Model License** — uso comercial permitido, con
atribución y la leyenda "Built on NVIDIA Cosmos". Datasets de NVIDIA de G1: CC-BY-4.0.

## 8. Decisiones del usuario (bloquean pasos)

1. **Camino A o B** (§3.1) — recomendado A. Bloquea el paso 1A (qué columnas de acción se usan).
2. **Casco** — **postergado 2026-10-13**: solo si la puerta 1C lo pide. Si llega: Quest 3 (lo
   más barato, ~USD 500, sirve para A), PICO 4 Ultra Enterprise (sirve para A y deja abierto B),
   Vision Pro.
3. **GPU** — indispensable (confirmado por el usuario 2026-10-13). Opciones con precios en el
   paso 1 (2026-10-16); recomendado empezar alquilando. Bloquea 1A, 1B y el paso 5. El paso 0
   está hecho (pestaña Joints, 2026-10-13/16).
4. **Cámaras de muñeca**: sí/no/después.
5. **Primera tarea**: cuál, con qué objetos.

## Fuentes (consultadas 2026-10-13)

- Isaac-GR00T: https://github.com/NVIDIA/Isaac-GR00T (README; `getting_started/hardware_recommendation.md`,
  `real_world_deployment.md`, `policy.md`; `scripts/deployment/README.md` para las latencias)
- Modelo: https://huggingface.co/nvidia/GR00T-N1.7-3B · checkpoint G1 real `nvidia/GR00T-N1.7-ApplePnP-V1`
- Curso NVIDIA G1 real (68 %, 200 episodios, NEW_EMBODIMENT):
  https://docs.nvidia.com/learning/physical-ai/gr00t-e2e-workflow/latest/real-robot-workflow/real-overview.html
- Issues: #414 (MSE vs. robot), #574/#590/#583 (G1 sim 0-1 %), #650 (REAL_G1 zero-shot),
  #712 (Orin), #575 (FP8 en Orin) — en github.com/NVIDIA/Isaac-GR00T/issues
- Teleop: https://github.com/unitreerobotics/xr_teleoperate · https://github.com/unitreerobotics/teleimager
- Datos y deploy: https://github.com/unitreerobotics/unitree_IL_lerobot
- Sim: https://github.com/unitreerobotics/unitree_sim_isaaclab
- Camino B: https://github.com/NVlabs/GR00T-WholeBodyControl ·
  https://nvlabs.github.io/GR00T-WholeBodyControl/tutorials/vla_workflow.html ·
  recalentamiento: issues #174, #85, #71 · reporte en G1 real:
  https://dev.classmethod.jp/articles/nvidia-gear-sonic-g1-teleope/
- Licencia de pesos: https://www.nvidia.com/en-us/agreements/enterprise-software/nvidia-open-model-license/
- Datasets de referencia: `unitreerobotics/G1_Dex3_ToastedBread_Dataset` (418 ep., 28-D, 4 cámaras),
  `unitreerobotics/G1_WBT_Inspire_Pick_Up_Drinks_v0`, `nvidia/PhysicalAI-Robotics-GR00T-Teleop-G1`
