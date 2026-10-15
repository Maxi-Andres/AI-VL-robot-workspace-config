# Plan · Control articular del G1 desde la app (antes que GR00T)

> Parte del ROADMAP. Escrito el **2026-10-13**, a pedido: mientras se consigue el servidor con GPU
> para GR00T (`G1-GROOT.md` paso 1), primero esto. **Qué es:** una pestaña de la app con el G1
> en 3D, que copia en vivo la posición real del robot; se toca una articulación (el codo, un
> dedo, una rodilla) y se mueve un poco. Bajo nivel, pero con una interfaz fácil.
>
> Cubre y amplía el **paso 0 de `G1-GROOT.md`** (brazo y mano por código) y sirve para
> **diagnosticar la inclinación hacia atrás** de `G1.md` §6.4 (ceros de las piernas).
> Datos del robot leídos por DDS el 2026-10-13; lo que dice "a verificar" no se probó todavía.

---

## 1. Qué se puede mover, y por dónde

| Grupo | Tópico | Quién equilibra | Cuándo |
|---|---|---|---|
| Brazos (7 + 7) y cintura (3) | `rt/arm_sdk`: mezcla por peso en `motor_cmd[29].q` (kNotUsedJoint) | **PC1, como siempre** | Robot parado en el piso, modo Regular (500) |
| Dedos **BrainCo** (6 + 6) | Modbus RTU por `/dev/ttyUSB1-2` desde PC2 (J4). **No** `rt/dex3/*` | No afecta | Siempre que la mano esté libre |
| **Piernas (6 + 6)** | `rt/lowcmd`, con PC1 **apagado** (`MotionSwitcherClient::ReleaseMode`) | **Nadie** | **Solo colgado** de una grúa o arnés |

Las piernas no se pueden mover "un poco" con el robot parado: para escribir en ellas hay que
sacarle el control a PC1, y desde ese momento nadie lo equilibra. Colgado da igual, y es
justamente como se ven los ceros de las articulaciones.

La cintura: **solo el yaw se mueve en este robot.** Reporta `mode_machine` 6, que en la tabla de
`g1_description` es la variante *lock waist* (`g1_29dof_lock_waist_with_hand_rev_1_0`): roll y
pitch son articulaciones FIJAS en el URDF, y en la telemetría marcan q 0, torque 0 y
**temperatura 0** — un motor que existe nunca marca 0 °C. O sea, no es el bloqueo de la app: no
hay motor (deducido el 2026-10-13 de esas tres cosas; no probado mandándoles nada).

## 2. Arquitectura

```
navegador (/joints)                    esta PC                       PC2 del G1
three.js + urdf-loader  ──WebSocket──▶ AI-VL-backend  ──▶ (executor) ──▶ relay_server.py ──stdin──▶ g1_joint_sender ──DDS──▶ 🤖
  dibuja el estado         estado ◀──   /ws/joints        tiene el        token, auditoría,          límites, velocidad,
  manda destinos                                          token           sesión on/off              rampa de peso, dead-man
```

- **`g1_joint_sender`** (C++, `robot-command-relay/src/`, hecho en J2): lee `rt/lowstate` y el
  FSM, escribe `rt/arm_sdk` (y más adelante las manos y, colgado, `rt/lowcmd`). **La seguridad
  vive en `joint_ctl_core.hpp`** (§4), C++ puro sin SDK, testeado en CI; no en el navegador.
- **`relay_server.py`**: `POST /joints/control` (take / target / keepalive / release) con una
  sesión por vez; lanza `g1_joint_sender` al tomar y el proceso termina al soltar. Los destinos
  van por HTTP, no por el UDP de `move` (a ~10 por segundo alcanza; UDP queda como mejora si
  sobre LTE se nota).
- **Backend**: `/ws/joints` (ver, solo lectura) y **`/ws/joint-control`** (mover), separados a
  propósito. El token del relay y el id de sesión nunca llegan al navegador.
- **Modelo 3D**: cuerpo lock-waist + manos **Inspire DFQ**, de `g1_description` en
  `~/Documents/LuckyEngine/Projects/Walking Pick and Place/Assets/Robots/g1_description/`,
  mallas reducidas a 6.1 MB.
- Solo por el relay, no por DDS directo desde esta PC: un solo camino que asegurar.

## 3. Pasos

Cada paso tiene **cómo se sabe que está hecho**. No se pasa al siguiente sin eso.

> **Estado 2026-10-15: J0 ✅, J2 ✅ (probado con el robot), J3 construido** (todos los brazos +
> cintura, rango completo; falta probarlo con el robot), **J1 construido** — su diagnóstico de
> las piernas colgado sigue pendiente. **Corrección del 2026-10-14: las manos son
> Inspire de cinco dedos, no Dex3-1** (el usuario lo vio en el robot): el modelo 3D se rehízo
> con manos Inspire, el puente dejó de leer `rt/dex3/*` y J4 cambia (abajo). Lo construido en
> J0/J1:
>
> - **PC2:** `robot-command-relay/src/g1_joint_bridge.cpp` — lee `rt/lowstate` (desde el
>   2026-10-14 ya no las Dex3) y escribe una línea JSON por tick (30 Hz). **Sin publisher: no puede mover el robot.** El relay
>   lo arranca con el primer visor de `GET /joints/stream` y lo para 10 s después del último;
>   guarda solo la línea más nueva (un visor lento saltea, no frena a nadie); máximo 4 visores.
>   Probado contra un publicador DDS falso, y `tests/test_joint_stream.py` (9 tests).
> - **Executor:** `GET /joints/stream?robot=g1` lo pasa tal cual, con el token puesto acá. Se
>   decidió el salto **por el executor**, como el video: el token queda en un solo proceso.
>   **Bug encontrado y arreglado de paso:** `_relay_for` usaba solo el `RELAY_TOKEN` compartido,
>   así que todo lo que pasaba por ahí hacia el G1 (también la config de video) iba con el token
>   del Go2 → 401. Ahora usa `G1_RELAY_TOKEN` como el resto. Tests: `test_joint_stream_proxy.py`.
> - **Backend:** `WS /ws/joints` — la línea más nueva por visor, y siempre un último mensaje
>   `{"error", "final": true}` que dice por qué se cortó. `tests/test_joint_stream.py` (4).
> - **Frontend:** pestaña **Joints** (`/joints`): el G1 en 3D (three.js + urdf-loader), color por
>   temperatura, inclinación por la IMU, inspector con ángulo / rango / torque / temperatura, la
>   tabla **piernas izquierda vs derecha** (espejada) y la lista de las 43 articulaciones.
>   **"Recorded walk"** (o `/joints#replay`) reproduce la caminata grabada hoy: con el robot
>   apagado ya se ve caminar con las rodillas dobladas, o sea la tabla y los signos de las
>   piernas están bien. Modelo: 49 mallas reducidas de 31 a 5.4 MB
>   (`scripts/build_g1_model.py`); la grabación: `scripts/build_g1_sample.py`.
>
> **Para probar J1 con el robot:** en PC2 `git pull && ./build.sh && sudo systemctl restart
> robot-command-relay` (el relay del G1 tiene que estar instalado: paso 6 de la página Robot).
> En esta PC reiniciar el executor del contenedor y correr `run.sh` (reconstruye el frontend).
> Abrir Joints → Live robot.

### J0 — Preparación (nada se mueve) ✅ 2026-10-13
- [x] Tabla índice del SDK ↔ URDF: `AI-VL-frontend/src/lib/g1Joints.ts`, con un test que la
      cruza contra el URDF que dibuja la página. Manos: los 6 motores de la Inspire por nombre
      del URDF; el orden en el que los reporte su servicio se fija en J4.
- [x] Mallas reducidas en `AI-VL-frontend/public/g1/`. **Falta confirmar la licencia** de
      `g1_description` (repos `unitree_ros`/`unitree_mujoco` de Unitree, BSD-3 según recuerdo,
      no verificado) antes de commitearlas.
- [x] Salto: por el executor (ver arriba).
- **Hecho cuando:** la tabla está escrita y el modelo se dibuja en una página de prueba.

### J1 — Visor 3D en vivo, solo lectura (riesgo cero)
- [x] Pestaña nueva en el header (`/joints`): el robot en 3D, girable, copiando `lowstate` a
      ~30 Hz. Las manos se dibujan quietas hasta J4. (Construido; falta verlo con el robot.)
- [x] Al pasar el mouse por una articulación: ángulo, torque y temperatura. Color por
      temperatura (los mismos datos del tablero de Splunk).
- [ ] **Diagnóstico de la inclinación, sin mover nada:** robot colgado y en amortiguado
      (piernas sueltas, caen derechas por gravedad). Si el dibujo muestra la cadera, la rodilla
      o el tobillo doblados mientras la pierna real está vertical, ese es el error de cero.
      Confirmar con el inclinómetro del celular.
- **Hecho cuando:** se mueve un brazo a mano (robot amortiguado) y el dibujo lo sigue para el
  mismo lado en las 29 articulaciones, con menos de 200 ms de retraso. (Los dedos, en J4.)

### J2 — Un codo, por `rt/arm_sdk` — ✅ probado con el robot 2026-10-14

> **Prueba con el robot (2026-10-14, a la noche; 02:42-02:44 en el reloj del robot):** cuatro
> sesiones, los dos codos, el deslizador movido rápido (destinos de 0.38 a 1.58 rad en menos de
> 1 s: el robot igual fue a 0.5 rad/s y todo quedó dentro de ±0.6 rad). Soltar anduvo siempre
> (rampa de 2 s, el sender terminó solo), y en una sesión los stop del Drive (HTTP y UDP)
> soltaron el brazo como corresponde. Motores después: **0 errores**, máximo 48 °C (muñeca
> izquierda), codos 45/42 °C, torque de los codos −1.4 a −2.6 N·m. El usuario: "anda bien".
- [x] `g1_joint_sender` + `joint_ctl_core.hpp` (las reglas, §4), a partir de
      `g1_arm7_sdk_dds_example.cpp` (leído, no parcheado). Habilitados: los dos codos
      (`JOINT_CTL_ALLOW`). Test del núcleo en CI (`tests/test_joint_ctl_core.py`, 34 chequeos).
      **Verificado por DDS** con una copia que finge el FSM 500 y un suscriptor a `rt/arm_sdk`:
      el peso sube 0→1 en 2 s, el codo izquierdo (índice 18) va de 0.18 a 0.60 rad a 0.5 rad/s,
      el derecho no se mueve, el peso baja a 0 y el proceso termina.
- [x] Relay: `POST /joints/control`, una sesión por vez con id; al tomar manda `stop_move`;
      mientras está tomado **rechaza `move` y las acciones de brazo y baile** (HTTP 409 y UDP),
      y un `stop_move` desde cualquier lado suelta el brazo. Tests: `test_joint_control.py`.
- [x] Executor `POST /joints/control?robot=g1` (token acá; en DRY_RUN solo deja pasar el
      release) y backend `/ws/joint-control`: **cerrar la pestaña suelta el brazo** (probado).
- [x] Página: panel "Move" — "Take control", los codos, deslizador ±5° con rango recortado,
      "Back to where it started", "Release". Fantasma azul translúcido del antebrazo en el
      destino; el sólido es siempre la lectura del robot.
- [x] **Probado de punta a punta en esta PC (2026-10-14)**, navegador → backend → executor →
      relay → sender reales, con un robot falso por DDS: tomar, subir 30°, soltar con su
      rampa, y cerrar la pestaña con el brazo tomado. Encontró y se arreglaron: el sender no
      terminaba al soltar (el `exit()` esperaba el lock de stdin → el relay ahora además lo
      mata a los 3 s), el release se perdía si el servidor cancelaba el handler, y el modelo 3D
      no aparecía tras un remontaje rápido (bug de J1: el LoadingManager contaba mal).
- **Para probar con el robot:** en PC2 `git pull && ./build.sh && sudo systemctl restart
  robot-command-relay`; en esta PC reiniciar el executor del contenedor y correr `run.sh`.
  Robot **parado quieto en Walk (FSM 500)**, alguien con el control remoto en la mano. Joints →
  Live robot → Take control → Left elbow → +5° de a uno. Mirar que el fantasma y el brazo real
  vayan para el mismo lado. Release, y ver que el brazo vuelve a la pose de PC1 sin tirón.
- **Ojo:** en el dibujo, subir el ángulo del codo lo ESTIRA hacia abajo (parado, el robot lee
  ~56°). Por eso los botones dicen aumentar/disminuir y no subir/bajar. Confirmarlo con el robot
  es parte de la prueba.
- **Hecho cuando:** el codo se mueve 20° y vuelve, con PC1 equilibrando, y al cerrar la sesión el
  brazo vuelve solo a la pose de PC1 sin tirón.

### J3 — Los dos brazos y la cintura — construido 2026-10-15, falta probar con el robot
- [x] Las 15 articulaciones de §1 por `arm_sdk` (7 + 7 del brazo + cintura yaw), con **todo el
      rango del URDF** (menos 0.05 rad): el usuario pidió sacar el tope de ±34° de J2
      (`JOINT_CTL_EXCURSION` sigue existiendo, ahora 0 = apagado). Como un brazo con todo el
      rango puede chocar con el cuerpo, dos reglas nuevas en el núcleo (§4): **freno por
      choque** (una articulación que empuja > 60 % de su torque nominal 250 ms sin llegar a su
      destino se queda donde está) y **suelta a 75 °C**. Tests: 43 chequeos del núcleo; el relay
      verifica que su lista de articulaciones coincida con la del núcleo.
- [x] Página: un deslizador por articulación, agrupadas (cintura / brazo izq. / brazo der.),
      con el destino y el valor medido; clic en el robot selecciona la fila. "Everything back to
      where it started". El fantasma muestra solo lo que todavía no llegó (> 2°). Probado de
      punta a punta en esta PC (hombro −50°, cintura +20°, soltar).
- [x] **Probado con el robot 2026-10-15**: "anda bien", pero el usuario lo sintió **a tirones**
      y su compañero **trabó un brazo con la mano y siguió empujando**. Arreglado el mismo día:
      - tirones: el deslizador manda ~10 destinos/s y el brazo iba a velocidad fija → arrancaba
        y frenaba en seco cada vez. Ahora **aceleración limitada** (2 rad/s², `JOINT_CTL_MAX_ACC`)
        con una curva de frenado que llega al destino sin sobrepasarlo ni dar el último salto
        (test: pico de aceleración ≤ 2.3 rad/s² incluida la llegada), y **200 Hz** en vez de 50
        (verificado por DDS).
      - empuje: a kp 60, el 60 % de 25 N·m recién se alcanza ~14° atrás del comando. Ahora
        **30 % y 150 ms** (~7°; `JOINT_CTL_STALL_FRAC`/`_MS`), y la página avisa "<joint> pushed
        against something: it stopped where it was".
      Falta probar estos dos cambios con el robot.
- [ ] Poses guardadas (nombre → ángulos). STOP siempre visible (hoy: Release y el stop del
      Drive).
- **Para probar con el robot:** `git pull && ./build.sh && sudo systemctl restart
  robot-command-relay` en PC2 (nada más: los valores nuevos son los de por defecto) y `run.sh`
  acá. Primero movimientos chicos de cada articulación para confirmar el sentido; después uno
  grande lejos del cuerpo. **No probar el freno por choque contra el propio cuerpo a propósito
  la primera vez**: verlo con la mano de alguien frenando el antebrazo suavemente.
- **Hecho cuando:** se arma una pose de brazos completa desde la página y se vuelve a la
  inicial, sin desequilibrio y sin temperaturas raras.

### J4 — Los dedos (manos **BrainCo**, no Inspire ni Dex3)

> **⚠️ 2026-10-15, confirmado: son BrainCo (tipo Revo 2), no Inspire.** Las fotos del usuario
> muestran el anillo de luz verde en el dorso y la palma de goma negra; y las dos contestan por
> **Modbus RTU a 460800**: `/dev/ttyUSB1` id **127** (derecha) y `/dev/ttyUSB2` id **126**
> (izquierda) (lectura de 1 registro, fc 3 y 4). Van a una cajita en la espalda conectada por
> USB-C a PC2 (FTDI FT4232H); ese USB estaba suelto. Todo lo que dice "Inspire" abajo y en §1/§2
> quedó viejo: la investigación de abajo vale como descarte. **El modelo 3D de la app sigue con
> manos Inspire DFQ**: hay que cambiarlo por el de BrainCo.
>
> **Lo que dicen las fuentes (investigado 2026-10-15):**
> - Revo 2: de fábrica izquierda id 126 / derecha id 127, 460800 — coincide con lo medido.
> - Registros (Modbus RTU): leer posiciones 2000-2005 (fc 04), velocidad 2006-2011, corriente
>   2012-2017, estado del motor 2018-2023 (0 quieto, 1 andando, 2 trabado), botón 2025,
>   lado 901 (1 der., 2 izq.). Escribir posición+velocidad 1022-1033 (6 pares). Modo 937: 0 =
>   0..1000 normalizado (0 = abierta, 1000 = cerrada). Orden: pulgar flexión, pulgar rotación,
>   índice, medio, anular, meñique. Corriente de protección 930-935 (100-1500 mA, de fábrica
>   500). Hasta 500 Hz. El registro 0 no existe en el mapa (por eso leía 0).
> - **No escribir** 903 (reset de fábrica), 900 (OTA), 1000 (id), 1001 (baud), 1009 (reinicio),
>   ni 1068 = 0; ni los modos de corriente/PWM (empujan hasta trabarse).
> - Unitree: `unitreerobotics/brainco_hand_service` (C++, PC2, SDK cerrado de BrainCo) publica
>   `rt/brainco/{left,right}/state` y escucha `.../cmd` (`unitree_go` MotorCmds_/MotorStates_,
>   6 valores 0..1) a 100 Hz. **Al arrancar abre las manos a toda velocidad.** Ojo: el
>   `robot_hand_brainco.py` de xr_teleoperate parece cruzar los dos motores del pulgar
>   (verificar moviendo uno solo).
> - Modelo 3D: `unitree_ros/robots/g1_with_brainco_hand/` (BSD-3; 6 activas + mimic por mano:
>   `{l,r}_thumb_metacarpal`, `thumb_proximal`, `{index,middle,ring,pinky}_proximal`).
> - Fuentes: github.com/unitreerobotics/brainco_hand_service, brainco-hz.com/docs/revolimb-hand
>   (revo2: modbus_foundation, parameters, faq), github.com/unitreerobotics/unitree_ros
>   (robots/g1_with_brainco_hand), github.com/unitreerobotics/xr_teleoperate.
>
> Plan: leer las manos con Modbus directo desde PC2 (sin el SDK cerrado) en el puente, mostrar
> los dedos en Joints, y después moverlas con velocidad y corriente bajas.

> **Revisado 2026-10-15 en el robot y en las fuentes.** En el robot: en `192.168.123.0/24` solo
> contestan PC1 (.161), PC2 (.164) y el lidar Mid-360 (.120); PC2 no tiene ningún
> `/dev/ttyUSB*` (por USB solo la RealSense y el Bluetooth); no corre ningún servicio de manos.
> Las manos tienen luz (están alimentadas) pero **nadie les habla**, por eso tampoco la app de
> Unitree las mueve. En las fuentes (investigado con agente, ver links abajo) **el firmware no
> maneja manos Inspire**: siempre es un programa en PC2 que hay que correr uno:
>
> - **DFX/DFQ (RS485, sin sensores táctiles):** un adaptador USB-RS485 por mano, enchufado a
>   PC2 (`/dev/ttyUSB1`/`2` en el código). Servicio `unitreerobotics/DFX_inspire_service`
>   (`sudo ./inspire_g1`); DDS `rt/inspire/cmd` y `rt/inspire/state` (`unitree_go`
>   MotorCmds_/MotorStates_, 12 valores 0..1 con 1 = abierta: 0-5 derecha, 6-11 izquierda, cada
>   una meñique, anular, medio, índice, flexión del pulgar, rotación del pulgar).
> - **FTP (táctil, Ethernet, Modbus TCP puerto 6000):** IP de fábrica **192.168.11.210** (las
>   dos manos igual); Unitree las configura en 123.210 (izq.) / 123.211 (der.). Servicio
>   `inspire_hand_ws`; DDS `rt/inspire_hand/ctrl|state|touch/{l,r}`.
> - `rt/dex3/*` lo publica un servicio residente del robot para la Dex3-1; `rt/hand_sdk` son 4
>   motores de mano dentro de `ai_sport`. Ninguno es la Inspire.
> - La luz de la mano solo dice que tiene 24 V, no que se comunique.
>
> Fuentes: github.com/unitreerobotics/DFX_inspire_service, github.com/unitreerobotics/xr_teleoperate
> (README §3.2, issues #46 y #48, `teleop/robot_control/robot_hand_inspire.py`),
> github.com/NaCl-1374/inspire_hand_ws (manual FTP).

- [x] **2026-10-15, el usuario enchufó un adaptador** a PC2: FTDI **FT4232H** genérico (4 puertos,
      `/dev/ttyUSB0-3`, en el hub interno `1-2.2`), el tipo de placa de las DFQ. Se le dio a
      `unitree` el grupo `dialout` para probar sin sudo. **Ninguna respuesta**: escucha pasiva
      1 s por puerto (silencio), y solo tramas de LECTURA (Inspire 0x11 posición, Modbus 0x03)
      en los 4 puertos × 9 velocidades (9600 a 1 M) × ids 1-2, más ids 1-16 a 115200. Lo más
      probable: los cables RS485 de las manos no llegan a ese adaptador, o A/B invertidos.
      (Ojo: la primera prueba que se pasó tenía mal el checksum, 0x2A en vez de 0x32; la
      segunda y estas ya lo tenían bien.)
- [ ] **Mirar el robot**: ¿hay adaptadores USB-RS485 sueltos o cables de las muñecas sin
      enchufar (→ DFQ), o un conector Ethernet y yemas táctiles (→ FTP)? La etiqueta del modelo
      está en la mano.
- [ ] Si es FTP: buscarla en su IP de fábrica 192.168.11.210 (una mano por vez: las dos tienen
      la misma). Ojo, agregarle una IP a `eth0` de PC2 puede cambiar la interfaz que usa DDS.
- [ ] Primera prueba **solo leyendo** (DFQ: la trama de lectura de posición a 115200; FTP: leer
      registros por Modbus). **No** correr `inspire_g1` ni `ModbusDataHandler` como prueba:
      empiezan a mandar comandos.
- [ ] Instalar y correr en PC2 el servicio de esa mano (el de Unitree para Inspire), primero
      solo leyendo: que el puente publique sus 6 + 6 valores y el dibujo los siga.
- [ ] Mover con fuerza baja. Atajos: abrir, cerrar, pinza. Dedo por dedo con el mismo fantasma.
- **Hecho cuando:** cada dedo se mueve desde la página y la mano agarra y suelta un objeto
  blando.

### J5 — Modo colgado: las piernas por `rt/lowcmd`
- [ ] Requisito físico: grúa o arnés que sostenga todo el peso, con los pies sin tocar el piso.
- [ ] Entrar: robot colgado y amortiguado → `ReleaseMode` hasta que `CheckMode` devuelva vacío
      (como `g1_ankle_swing_example.cpp`). Copiar `mode_machine` del `lowstate`, `mode_pr` en PR,
      CRC en cada mensaje.
- [ ] Al entrar, el destino de cada articulación es **su posición actual**, para que nada salte.
      Ganancias bajas.
- [ ] Salir: la forma de devolverle el control a PC1 está **a verificar** (`SelectMode` o
      reinicio). Hasta saberlo, se sale con el robot colgado.
- [ ] **Diagnóstico:** mandar las piernas a cero y comparar con el dibujo y con el inclinómetro.
      Mover cada articulación por separado para confirmar el sentido.
- **Hecho cuando:** cada articulación de las piernas se mueve desde la página, se sabe si los
  ceros están corridos y en cuánto, y se vuelve a caminar normal después.

### J6 — Grabar movimientos (puente a GR00T)
- [ ] Grabar la secuencia de destinos + estado + cámara mientras se mueve desde la página.
- [ ] Guardar en formato LeRobot, el que piden ACT y GR00T.
- **Hecho cuando:** una grabación se reproduce igual en el robot. Esto es una forma más de
  juntar demostraciones sin casco (`G1-GROOT.md` paso 1C, rama "Sí").

## 4. Seguridad (en `g1_joint_sender`, no en el navegador)

Lo que quedó en `joint_ctl_core.hpp` (J2), con sus valores por defecto; cada uno tiene su test:

- Solo se toma con el robot en Walk (FSM 500/501, `JOINT_CTL_FSM_OK`) y con `lowstate` fresco
  (< 100 ms). Si el FSM cambia (amortiguado, caída, el control remoto), o no se puede leer por
  2 s, o el estado se pierde por 0.5 s: suelta.
- Al tomar, el destino de cada articulación es donde ESTÁ; el peso sube de 0 a 1 en 2 s.
- Solo aceptan destino las de `JOINT_CTL_ALLOW` (J2: los codos; desde J3 todas las de brazo y
  la cintura yaw); las demás se sostienen quietas. La cintura roll/pitch nunca (no tienen motor).
- Destino recortado al rango del URDF menos 0.05 rad; en J2 también a 0.6 rad (~34°) de donde
  estaba al tomar, desde J3 apagado por defecto (`JOINT_CTL_EXCURSION=0`).
- Velocidad 0.5 rad/s (`JOINT_CTL_MAX_VEL`, tope 1.0): el sender interpola, el navegador solo
  manda destinos. kp 60 / kd 1.5, como el ejemplo de Unitree.
- Dead-man: sin mensajes 1 s → se congela donde está; 5 s → suelta. La página manda un latido
  cada 250 ms. Si stdin se cierra (el relay murió) → suelta.
- Soltar también es una rampa (2 s); después un último mensaje con peso 0 y el proceso termina.
- (J3) Freno por choque: una articulación con torque medido > 30 % del nominal del URDF (brazo
  25 N·m → 7.5; muñeca pitch/yaw 5 → 1.5; cintura 88 → 26) durante 150 ms, estando a más de 0.05
  rad de su comando, deja de empujar: comando y destino pasan a donde está. (Era 60 % / 250 ms
  hasta el 2026-10-15: con el brazo trabado a mano seguía empujando.)
- Aceleración limitada a 2 rad/s² y 200 Hz (2026-10-15, por los tirones).
- (J3) Cualquier motor sostenido a 75 °C o más → suelta (la alarma de telemetría es 80).
- No caminando: al tomar, el relay manda `stop_move`; mientras está tomado rechaza `move` y las
  acciones de brazo; un `stop_move` desde cualquier lado suelta el brazo.
- Modo colgado solo con confirmación explícita en la página ("el robot está colgado") y nunca
  si el robot está en un modo de caminar.
- Mientras el robot siga echado para atrás (§6.4), movimientos chicos: mover los brazos le
  corre el centro de masa.
- Operador con el control remoto en la mano en todas las pruebas con movimiento.

## 5. Decisiones abiertas

- ~~Salto backend → relay~~: por el executor (2026-10-13).
- ~~Dependencias del frontend~~: `three` 0.169.0 y `urdf-loader` 0.12.3, fijadas.
- ~~Por dónde van los destinos~~: HTTP por el executor, socket propio en el backend (2026-10-14).
- Qué FSM habilitan el control (`JOINT_CTL_FSM_OK`, hoy 500 y 501): ¿hace falta 801 (Run)?
- Modelo de mano Inspire (DFQ o FTP): a confirmar con el robot (J4).
- Licencia de las mallas en `AI-VL-frontend/public/g1/` (a confirmar antes de commitear).
- Grúa o arnés para J5: ¿hay uno, o hay que conseguirlo?
