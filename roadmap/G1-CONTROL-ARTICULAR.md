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
| Dedos Dex3-1 (7 + 7) | `rt/dex3/{left,right}/cmd`; estado en `.../state` | No afecta | Siempre que la mano esté libre |
| **Piernas (6 + 6)** | `rt/lowcmd`, con PC1 **apagado** (`MotionSwitcherClient::ReleaseMode`) | **Nadie** | **Solo colgado** de una grúa o arnés |

Las piernas no se pueden mover "un poco" con el robot parado: para escribir en ellas hay que
sacarle el control a PC1, y desde ese momento nadie lo equilibra. Colgado da igual, y es
justamente como se ven los ceros de las articulaciones.

La cintura: con cintura bloqueada (`G1_WAIST_LOCK=1`, FSM 500) roll y pitch quedan en 0.00° con
torque 0 (medido, `G1.md` §6.4); solo el yaw responde. Las tres responden en 501.

## 2. Arquitectura

```
navegador (/joints)                    esta PC                       PC2 del G1
three.js + urdf-loader  ──WebSocket──▶ AI-VL-backend  ──▶ (executor) ──▶ relay_server.py ──stdin──▶ g1_joint_sender ──DDS──▶ 🤖
  dibuja el estado         estado ◀──   /ws/joints        tiene el        token, auditoría,          límites, velocidad,
  manda destinos                                          token           sesión on/off              rampa de peso, dead-man
```

- **`g1_joint_sender`** (C++ nuevo, `robot-command-relay/src/`, mismo patrón que
  `g1_command_sender`): lee `rt/lowstate` y los dos `dex3/*/state`, escribe `rt/arm_sdk`, los
  `dex3/*/cmd` y, en modo colgado, `rt/lowcmd`. **La seguridad vive acá** (§4), no en el
  navegador, igual que el clamp y el dead-man de hoy viven en `sender_core.hpp`.
- **`relay_server.py`**: suma una sesión de articulaciones (abrir / cerrar), el estado en
  streaming hacia afuera (~30 Hz) y los destinos hacia adentro por el canal UDP con HMAC que
  ya usa `move`. Lanza `g1_joint_sender` solo mientras la sesión está abierta.
- **Backend**: un `/ws/joints` que hace de puente. El token del relay nunca llega al navegador.
- **Modelo 3D**: el URDF oficial `g1_29dof_with_hand_rev_1_0.urdf` (53 articulaciones, Dex3
  incluida), que ya está en disco en
  `~/Documents/LuckyEngine/Projects/Walking Pick and Place/Assets/Robots/g1_description/`. Usa 49
  mallas STL, **31 MB**: hay que reducirlas (objetivo < 5 MB) antes de servirlas.
- Solo por el relay, no por DDS directo desde esta PC: un solo camino que asegurar.

## 3. Pasos

Cada paso tiene **cómo se sabe que está hecho**. No se pasa al siguiente sin eso.

### J0 — Preparación (nada se mueve)
- [ ] Tabla índice del SDK (0-28 y 0-6 de cada Dex3) ↔ nombre de articulación del URDF. El
      lector de telemetría ya tiene los 29 nombres (`g1_telemetry_reader.cpp`, `build_motors`).
- [ ] Mallas reducidas y servidas por la app. Verificar la licencia de `g1_description` antes de
      meterlas en un repo.
- [ ] Decidir el salto backend → relay (directo o por el executor, que hoy guarda el token).
      Leer antes `AI-VL-ecosystem/docs/TRANSPORT_SDK_VS_ROS2.md`.
- **Hecho cuando:** la tabla está escrita y el modelo se dibuja en una página de prueba.

### J1 — Visor 3D en vivo, solo lectura (riesgo cero)
- [ ] Pestaña nueva en el header (`/joints`): el robot en 3D, girable, copiando `lowstate` y
      las Dex3 a ~30 Hz.
- [ ] Al pasar el mouse por una articulación: ángulo, torque y temperatura. Color por
      temperatura (los mismos datos del tablero de Splunk).
- [ ] **Diagnóstico de la inclinación, sin mover nada:** robot colgado y en amortiguado
      (piernas sueltas, caen derechas por gravedad). Si el dibujo muestra la cadera, la rodilla
      o el tobillo doblados mientras la pierna real está vertical, ese es el error de cero.
      Confirmar con el inclinómetro del celular.
- **Hecho cuando:** se mueve un brazo a mano (robot amortiguado) y el dibujo lo sigue para el
  mismo lado en las 29 articulaciones y los 14 dedos, con menos de 200 ms de retraso.

### J2 — Un codo, por `rt/arm_sdk`
- [ ] `g1_joint_sender` con UNA articulación habilitada, a partir de
      `unitree_sdk2/example/g1/high_level/g1_arm7_sdk_dds_example.cpp` (leer, no parchear).
- [ ] En la página: tocar el codo, aparece un fantasma transparente en el destino, deslizador
      o arrastre, botón "Tomar control". Al soltar, el robot va despacio.
- [ ] El relay rechaza las acciones de brazo mientras la sesión está abierta (evita el 7400).
- **Hecho cuando:** el codo sube 20° y vuelve, con PC1 equilibrando, y al cerrar la sesión el
  brazo vuelve solo a la pose de PC1 sin tirón.

### J3 — Los dos brazos y la cintura
- [ ] Todas las articulaciones de §1 por `arm_sdk`, con límites del URDF.
- [ ] Poses guardadas (nombre → ángulos), "volver a la pose inicial", y STOP siempre visible.
- **Hecho cuando:** se arma una pose de brazos completa desde la página y se vuelve a la
  inicial, sin desequilibrio y sin temperaturas raras.

### J4 — Los dedos Dex3
- [ ] `dex3/*/cmd` con ganancia baja, base `unitree_sdk2/example/g1/dex3/g1_dex3_example.cpp`.
- [ ] Atajos: abrir, cerrar, pinza. Dedo por dedo con el mismo fantasma.
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

- Destino recortado a los límites del URDF, con margen.
- Velocidad máxima por articulación (empezar con ~0.5 rad/s); el sender interpola, el navegador
  solo manda destinos.
- Al tomar `arm_sdk`, el peso sube de 0 a 1 en 2 s; al soltar, baja igual.
- Dead-man: si no llega un destino o un latido en ~300 ms, se congela y suelta despacio. Si
  stdin se cierra (el relay murió), suelta.
- Modo brazos solo con el robot parado en Regular, no caminando.
- Modo colgado solo con confirmación explícita en la página ("el robot está colgado") y nunca
  si el robot está en un modo de caminar.
- Mientras el robot siga echado para atrás (§6.4), movimientos chicos: mover los brazos le
  corre el centro de masa.
- Operador con el control remoto en la mano en todas las pruebas con movimiento.

## 5. Decisiones abiertas

- Salto backend → relay: directo o por el executor (J0).
- Dependencias nuevas del frontend: `three` y `urdf-loader`.
- Dónde viven las mallas reducidas y su licencia.
- Grúa o arnés para J5: ¿hay uno, o hay que conseguirlo?
