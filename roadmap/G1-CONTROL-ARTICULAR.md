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
| Dedos **Inspire** (6 + 6) | El servicio propio de la mano (a instalar, J4). **No** `rt/dex3/*`: eso es de la otra mano | No afecta | Siempre que la mano esté libre |
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

> **Estado 2026-10-14: J0 ✅, J1 y J2 construidos y probados sin robot.** Falta probar los dos
> con el robot (abajo, "Para probar J1" y en J2). **Corrección del 2026-10-14: las manos son
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

### J2 — Un codo, por `rt/arm_sdk` — construido 2026-10-14, falta probar con el robot
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

### J3 — Los dos brazos y la cintura
- [ ] Todas las articulaciones de §1 por `arm_sdk`, con límites del URDF.
- [ ] Poses guardadas (nombre → ángulos), "volver a la pose inicial", y STOP siempre visible.
- **Hecho cuando:** se arma una pose de brazos completa desde la página y se vuelve a la
  inicial, sin desequilibrio y sin temperaturas raras.

### J4 — Los dedos (manos Inspire, no Dex3)
- [ ] **Identificar el modelo** con el robot prendido: `ping 192.168.123.210` desde PC2 → FTP
      (Ethernet); un `/dev/ttyUSB*` de la mano → DFQ (RS485). El dibujo usa DFQ.
- [ ] Instalar y correr en PC2 el servicio de esa mano (el de Unitree para Inspire), primero
      solo leyendo: que el puente publique sus 6 + 6 valores y el dibujo los siga.
- [ ] Mover con fuerza baja. Atajos: abrir, cerrar, pinza. Dedo por dedo con el mismo fantasma.
- [ ] Ver qué publica `rt/dex3/*/state` en este robot (la otra mano): por curiosidad, no se usa.
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
- Solo aceptan destino las de `JOINT_CTL_ALLOW` (los codos); las otras 15 se sostienen quietas.
  La cintura roll/pitch nunca (no tienen motor).
- Destino recortado al rango del URDF menos 0.05 rad **y** a 0.6 rad (~34°) de donde estaba al
  tomar (`JOINT_CTL_EXCURSION`, tope 1.0 en el binario).
- Velocidad 0.5 rad/s (`JOINT_CTL_MAX_VEL`, tope 1.0): el sender interpola, el navegador solo
  manda destinos. kp 60 / kd 1.5, como el ejemplo de Unitree.
- Dead-man: sin mensajes 1 s → se congela donde está; 5 s → suelta. La página manda un latido
  cada 250 ms. Si stdin se cierra (el relay murió) → suelta.
- Soltar también es una rampa (2 s); después un último mensaje con peso 0 y el proceso termina.
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
