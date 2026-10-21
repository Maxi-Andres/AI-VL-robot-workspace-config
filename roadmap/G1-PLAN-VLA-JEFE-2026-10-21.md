# Roadmap técnico — Unitree G1 EDU: VLM/VLA, navegación y manipulación

**Versión:** 1.0  
**Fecha:** 21 de octubre de 2026  
**Objetivo:** convertir el Unitree G1 EDU en un robot capaz de comprender órdenes, localizar objetos, desplazarse hasta ellos, manipularlos con las manos BrainCo Revo 2 Touch, transportarlos, depositarlos y verificar el resultado.

> **Principio rector:** la IA propone objetivos y acciones; la ejecución física se valida y controla localmente. El equilibrio y la locomoción de bajo nivel permanecen a cargo de la **PC1 de Unitree** por ahora. No enviar comandos de control articular en lazo cerrado directamente desde la nube.

## 1. Estado real del sistema

### 1.1 Hardware y plataforma confirmados

| Componente | Estado / especificación |
|---|---|
| Robot | Unitree G1 EDU, **29 DoF de cuerpo** |
| Manos | **BrainCo Revo 2 Touch**, cinco dedos; actuadores adicionales a los 29 DoF |
| Computadora embarcada | NVIDIA Jetson Orin |
| Controlador de equilibrio y piernas | **PC1 Unitree**, activo y responsable del control actual |
| Edge server | **Minisforum Atom G1** |
| GPU del edge | NVIDIA RTX 5060 |
| Memoria edge | **32 GiB RAM utilizable** |
| Sistema operativo | Ubuntu **22.04.5** |
| Entorno de desarrollo | Dev Container |
| Middleware | ROS 2 **Humble** |
| Detección | YOLO, actualmente en uso |
| Visión-lenguaje | Qwen VL, **nombre/checkpoint exacto por confirmar** (se mencionó “VL4”) |
| STT / TTS | Whisper / Piper, actualmente en uso; mejoras de audio diferidas |
| Audio | AudioHub del G1 alimenta Whisper |
| GPU cloud | Por contratar / evaluar (RunPod propuesto) |

### 1.2 Avances confirmados — **no volver a implementar desde cero**

- [x] **Control manual de bajo nivel de las articulaciones:** se pueden regular a voluntad sin IA.
- [x] **Control manual de bajo nivel de las manos Revo 2 Touch:** se pueden controlar a voluntad sin IA.
- [x] **Equilibrio y piernas:** gestionados por PC1 Unitree.
- [x] ROS 2 Humble operativo en el entorno de desarrollo.
- [x] YOLO integrado al proyecto.
- [x] Canal de audio hacia Whisper existente, aunque su calidad en ruido y a distancia es mejorable.

**Por verificar, no asumir:** interfaces reales del control manual (tópicos ROS 2, servicios, SDK o ambos), telemetría disponible, límites y velocidades de actuadores, feedback táctil, versión de Qwen, cámaras/profundidad, estado de integración entre locomoción y ROS 2, latencia de red, mecanismo de parada segura.

### 1.3 Alcance de la primera misión

**Orden ejemplo:** “Buscá la botella azul que está sobre la mesa, acercate, agarrala con la mano derecha, llevala a la otra mesa, soltala y confirmame que terminaste”.

**Primera versión práctica:** interiores controlados, piso libre, objetos livianos, una mesa o superficie fija, supervisión presencial y zona de exclusión de personas durante movimientos experimentales.

**Fuera de alcance inicial:** reemplazar PC1, entrenamiento de equilibrio desde cero, control de torque remoto, desplazamientos rápidos cargando objetos, manipulación cerca de personas sin validaciones adicionales.

---

## 2. Arquitectura de tres niveles

```text
                     CLOUD / RUNPOD (cómputo intensivo)
          +---------------------------------------------+
          | Qwen VL / razonamiento / Task Planner       |
          | VLA experimental: SmolVLA, pi0.5 o GR00T   |
          | Entrenamiento y evaluación offline         |
          +----------------------+----------------------+
                                 |
                    API autenticada + VPN
              (objetivos, observaciones, action chunks)
                                 |
                                 v
                       EDGE / MINISFORUM
          +---------------------------------------------+
          | Ubuntu 22.04.5 · Dev Container              |
          | ROS 2 Humble · RTX 5060 · 32 GiB RAM       |
          | YOLO · seguimiento · percepción/pose 3D    |
          | localización · planificación navegación    |
          | MoveIt 2 / IK · Robot Action Adapter       |
          | Safety Supervisor · BT / Action Server     |
          +----------------------+----------------------+
                                 |
                      Red local / ROS 2 / SDK
                                 |
                                 v
                       ROBOT / UNITREE G1 EDU
          +---------------------------------------------+
          | Jetson Orin · sensores · brazos             |
          | BrainCo Revo 2 Touch (control ya existente) |
          | PC1 Unitree -> marcha y equilibrio          |
          | Validación y ejecución de comandos locales  |
          +---------------------------------------------+
```

### Distribución de responsabilidades

| Función | Ubicación preferida | Motivo |
|---|---|---|
| Interpretación semántica visual | Cloud (o edge si cabe) | Inferencia VLM pesada |
| Planificación de misión | Cloud/edge | No requiere lazo de control rápido |
| YOLO, tracking y obstáculos inmediatos | Edge | Menor latencia |
| Reconstrucción/proyección 3D y TF | Edge | Se apoya en sensores y estado local |
| SLAM, mapa, planificación de ruta | Edge | Requiere consistencia local |
| Generación VLA de *bloques* de acciones | Cloud inicialmente; edge si viable | Evaluar rendimiento real |
| IK, control de brazos, dedos y validaciones | Edge/robot | Ejecución sensible a latencia y seguridad |
| Marcha, equilibrio, estabilización | **PC1 Unitree** | **No modificar en esta etapa** |
| Parada, watchdog y límites | Local, independiente del cloud | Seguridad ante fallas de red |

**Nota:** una GPU más grande acelera inferencia y entrenamiento, pero por sí sola no aporta coordenadas 3D, políticas entrenadas para Revo 2 Touch ni navegación segura.

---

## 3. Capacidades requeridas y estado

| Capacidad | Base tecnológica propuesta | Estado inicial |
|---|---|---|
| Detectar objetos | YOLO | Ya en uso |
| Comprender qué objeto pidió el usuario | Qwen VL + grounding | Integrar y evaluar |
| Estimar posición, orientación y profundidad | RGB-D/3D, calibraciones, TF | Verificar sensores / desarrollar |
| Reconocer estado y poses del robot | Lectura de joints, odometría, IMU, manos | Verificar interfaces |
| Mapa y localización | SLAM / fusión sensorial | Por verificar |
| Navegar evitando obstáculos | Planificador + puente PC1 | Por integrar y validar |
| Aproximación segura a superficies | Planificador de postura base/torso | Por desarrollar |
| Alcance de brazo | IK + MoveIt 2 o solución compatible | Bajo nivel manual ya disponible |
| Agarre de manos | Control BrainCo ya disponible + táctil | Bajo nivel manual ya disponible |
| Objetos durante transporte | Seguimiento + restricción de movimiento | Por implementar |
| Secuenciación de misiones | Behavior Tree / ROS 2 Actions | Por implementar |
| Recuperación de errores | Supervisor y estados de falla | Por implementar |
| Política aprendida VLA | SmolVLA / pi0.5 / GR00T | Por seleccionar / adaptar |
| Simulación y validación | Isaac Sim/Lab o MuJoCo | Por implementar o verificar |

---

## 4. Arquitectura del software de acción

### 4.1 Mantener y envolver los controladores manuales existentes

En vez de reescribir controladores de dedos y articulaciones, envolverlos con interfaces estándar y limitadas:

```text
Usuario / Planner / VLA
          |
          v
Behavior Tree / Task Orchestrator
          |
          v
Robot Action Adapter (nuevo)
  |-- verificaciones de estado y autorización
  |-- límites de posición/velocidad/esfuerzo
  |-- movimiento planificado + supervisión
  |-- detección de timeout y fallo
  |-- traducción de objetivos a comandos conocidos
          |
          +--> Control manual ya implementado: brazos/articulaciones
          +--> Control manual ya implementado: Revo 2 Touch
          +--> Interfaz segura de locomoción -> PC1 Unitree
```

**No asumir** que se permite controlar simultáneamente dos interfaces de bajo nivel sobre una misma articulación: establecer arbitraje de mando, modos mutuamente exclusivos y habilitación explícita.

### 4.2 Interfaces ROS 2 propuestas (a desarrollar o adaptar)

| Action / servicio conceptual | Entrada | Resultado esperado |
|---|---|---|
| `NavigateTo` | Pose destino | Llegada con tolerancia y estado de seguridad |
| `ApproachObject` | ID y pose de objeto | Base a distancia manipulable |
| `ReachPose` | Pose 6D del efector | Brazo posicionado sin colisión |
| `GraspObject` | ID objeto + mano + tipo de agarre | Agarre confirmado o error |
| `TransportObject` | Objetivo y restricciones de carga | Transporte vigilado |
| `PlaceObject` | Pose destino + mano | Objeto liberado de forma controlada |
| `VerifyTask` | Criterio observable | Éxito, incertidumbre o fallo |
| `StopMotion` | Origen de parada | Detención segura local |

Estos **nombres son propuestas de contrato**, no afirmaciones de que existan ya en Unitree o BrainCo.

### 4.3 Condiciones de seguridad obligatorias

- No permitir que la salida de un LLM/VLM/VLA se convierta directamente en comandos de torque.
- Limitar objetivos a un espacio de trabajo definido; verificar colisiones, límites articulares y velocidades.
- Registrar dueño actual del mando (manual, automático o recuperación); evitar conflictos.
- Implementar watchdog local y caducidad de comandos cloud.
- Si se pierde conectividad o queda incompleta una secuencia, transicionar a un estado local seguro adaptado a la postura/carga; **no asumir que detener bruscamente es siempre seguro**.
- Preservar el controlador PC1 para equilibrio y piernas; probar integración con sus interfaces soportadas.
- Supervisión presencial y parada de emergencia funcional durante todos los ensayos físicos.

---

## 5. Selección de modelos VLM/VLA

### 5.1 VLM — Qwen

Mantener el uso actual de Qwen para comprensión visual y lenguaje, pero confirmar **checkpoint exacto, parámetros, precisión, VRAM ocupada y latencia**. Integrarlo con YOLO y el estimador 3D. Qwen identifica objetivos y relaciones espaciales; **no sustituye** por sí solo la estimación métrica ni el control físico.

### 5.2 Candidatos VLA

| Modelo / familia | Papel sugerido | Cuidado principal |
|---|---|---|
| **SmolVLA (LeRobot)** | Primeras tareas de *pick-and-place* entrenadas con demostraciones del propio G1 | Adaptar observaciones y vector de acciones al robot/manos |
| **π₀.₅ / OpenPI** | Manipulación con políticas más capaces, para pruebas cloud | Requiere integración y datos; no es plug-and-play para BrainCo |
| **NVIDIA Isaac GR00T** | Línea de investigación de humanoides, coordinación de cuerpo completo | Confirmar variante, mapeo del embodiment y requisitos de entrenamiento |

**Elección de arranque:** primero lograr una manipulación determinística reproducible. Después evaluar **SmolVLA** como primer VLA entrenable. Comparar π₀.₅ y GR00T una vez que exista un dataset y métricas de referencia. No entrenar locomoción desde cero mientras PC1 resuelva ese control.

### 5.3 Mapeo de embodiment (obligatorio)

Documentar para cada observación y acción: nombres/orden de articulaciones, unidades (radianes/grados), límites, frecuencias, frames `tf2`, pose de mano, estado táctil, convenciones izquierda/derecha y latencia. Las manos Revo 2 Touch **no son intercambiables sin adaptación** con manos usadas para preentrenar otros VLA.

---

## 6. Cloud y GPU: estrategia sin sobredimensionar

**Proveedor inicial a evaluar:** [RunPod](https://www.runpod.io/). No desplegar nada irreversible antes de medir las necesidades.

| Carga | GPU de prueba | Criterio de elección |
|---|---|---|
| Qwen-VL para inferencia | L40S 48 GB | Ajustar al checkpoint y throughput real |
| SmolVLA pequeño | RTX 5060 local, si cabe; si no, L40S | Evitar gasto cloud si la latencia local es aceptable |
| π₀.₅ inferencia | L40S o A100 80 GB | Comprobar VRAM del checkpoint elegido |
| Ajuste fino/adaptación VLA | A100/H100 80 GB | Medir memoria, batch y duración real |
| Entrenamiento de modelos mayores / GR00T | GPU según receta oficial vigente | No presupuestar sin elegir modelo concreto |

**Mediciones para decidir:** GPU VRAM máxima, memoria host, tiempo por inferencia, tiempo de ida/vuelta Argentina ↔ región cloud, frecuencia de publicación de acciones, tasa de fallos, costo por sesión y costo con instancia detenida/almacenamiento. Precios de GPUs son variables y deben revisarse al contratar.

**Arquitectura cloud:** contenedor reproducible + endpoint privado autenticado, transporte seguro y parámetros auditables. Transmitir observaciones comprimidas/seleccionadas, no todo el video crudo si no es necesario. Retener logs y datasets evitando credenciales en archivos.

---

## 7. Roadmap de implementación por fases

### Fase 0 — Inventario, telemetría y seguridad (prioridad inmediata)

**Objetivo:** aprovechar el control manual ya existente y documentar sus contratos.

- [x] Confirmar G1 EDU de 29 DoF.
- [x] Confirmar Revo 2 Touch.
- [x] Confirmar control manual de articulaciones y manos.
- [x] Confirmar PC1 como responsable actual de equilibrio y piernas.
- [ ] Identificar tópicos ROS 2, servicios, SDK y mensajes usados para cada actuador.
- [ ] Verificar feedback de joint states, odometría, IMU, pinzas/manos y sensores táctiles.
- [ ] Confirmar cámaras y disponibilidad de profundidad / LiDAR.
- [ ] Identificar geometría URDF/MJCF y transformaciones TF del G1 29 DoF con Revo2.
- [ ] Establecer parada de emergencia, exclusión de personas, watchdog, límites y log de comandos.
- [ ] Registrar latencias reales de ROS 2 y control manual.

**Entregable:** inventario de interfaces (`interfaces.md`) + diagrama de TF + procedimiento de parada y recuperación.

**Criterio de salida:** control reproducible en modo manual, telemetría verificada y mecanismo de parada probado.

### Fase 1 — Manipulación determinística sin IA

**Objetivo:** un *pick-and-place* repetible con G1 inmóvil y objeto conocido.

- [ ] Envolver los controladores manuales existentes como acciones ROS 2.
- [ ] Integrar MoveIt 2 / IK con URDF correcto, colisiones y límites.
- [ ] Calibrar la transformación cámara → torso/brazo/mano.
- [ ] Programar poses pre-agarre, agarre, levantamiento y depósito.
- [ ] Incorporar sensores táctiles/realimentación para confirmar que el objeto quedó sostenido, si las interfaces exponen esos datos.
- [ ] Ejecutar series de ensayo sobre objeto liviano no frágil.

**Entregable:** `pick_place_demo` determinístico, sin nube y sin VLA.

**Criterio de salida propuesto:** 20 intentos documentados, tasa de éxito y fallos clasificados; sin incidentes de seguridad. Fijar umbral de éxito antes de pasar de fase.

### Fase 2 — Percepción métrica + navegación

**Objetivo:** pasar de “veo una botella” a “sé dónde está y cómo llegar”.

- [ ] Vincular bbox/segmentación de YOLO con profundidad o estimación 3D validada.
- [ ] Mantener tracking de cada objeto y su pose en frames ROS 2.
- [ ] Montar SLAM/localización y mapa de obstáculos según sensores disponibles.
- [ ] Conectar un planificador de ruta (Nav2 si encaja) a una interfaz de marcha **compatible con PC1**.
- [ ] Implementar aproximación con distancia de manipulación y postura base estable.
- [ ] Verificar degradación segura ante obstáculo, pérdida de pose o timeout.

**Entregable:** `navigate_and_approach_object` autónomo, sin agarrar.

**Criterio de salida:** llegar repetidamente a posiciones de manipulación con error medido y sin colisiones.

### Fase 3 — Datos de demostración para VLA

**Objetivo:** crear datos adecuados para entrenar una política sobre este G1 y las Revo2.

- [ ] Elegir formato de episodios y esquema de observaciones/acciones (por ejemplo LeRobot).
- [ ] Registrar cámaras con timestamp, poses articulares, IMU, acción emitida, estado de manos y contacto disponible.
- [ ] Capturar teleoperación/demostraciones exitosas y fallidas etiquetadas.
- [ ] Sincronizar tiempo, detectar frames perdidos y validar unidades.
- [ ] Separar entrenamientos y pruebas por escena y objetos.
- [ ] Versionar datasets y registrar consentimiento si se graba a personas.

**Entregable:** dataset reproducible de *pick-and-place* con especificación del vector de acciones.

**Criterio de salida:** episodios sincronizados, reproducibles y suficientes para iniciar experimentos; sin presuponer que un número fijo garantice aprendizaje.

### Fase 4 — Primer VLA de manipulación

**Objetivo:** generar acciones aprendidas, con supervisión local y hardware real.

- [ ] Implementar `observation_adapter` y `action_adapter` para G1 29 DoF + Revo2.
- [ ] Entrenar/evaluar SmolVLA contra baseline determinístico.
- [ ] Añadir validación local antes de ejecutar cada bloque de acciones.
- [ ] Probar primero en simulador; luego en robot inmóvil y supervisado.
- [ ] Medir porcentaje de agarres, fallos, latencia y recuperación.
- [ ] Sólo si aporta valor, ensayar π₀.₅ en la nube y comparar.

**Entregable:** política VLA capaz de agarrar/depositar objetos de prueba en condiciones acotadas.

**Criterio de salida:** mejora cuantificada o flexibilidad adicional respecto del baseline, manteniendo condiciones de seguridad.

### Fase 5 — Orquestación de tareas completas

**Objetivo:** encadenar visión, desplazamiento, alcance, agarre, transporte, depósito y verificación.

- [ ] Implementar Behavior Tree o máquina de estados en ROS 2.
- [ ] Exponer acciones `NavigateTo`, `ApproachObject`, `ReachPose`, `GraspObject`, `TransportObject`, `PlaceObject`, `VerifyTask`.
- [ ] Incorporar reintentos acotados, timeout y recuperación controlada.
- [ ] Ejecutar misión completa en entorno supervisado.
- [ ] Conectar órdenes semánticas de Qwen sin otorgarle acceso directo al bajo nivel.

**Entregable:** demostración end-to-end: **buscar → acercarse → agarrar → transportar → depositar → verificar**.

**Criterio de salida:** tasa de éxito medida de misión completa, registro de latencia por etapa y fallas explicables.

### Fase 6 — Mayor autonomía y GR00T / coordinación de cuerpo completo

**Objetivo:** expandir la variedad de tareas y estudiar coordinaciones complejas.

- [ ] Evaluar GR00T/π₀.₅ con adaptaciones específicas al embodiment.
- [ ] Incluir torso y dos manos con restricciones de equilibrio suministradas por PC1.
- [ ] Mejorar manipulación bimanual, recuperación de agarres y objetos nuevos.
- [ ] Probar generalización por iluminación, posición, superficies y objetos.
- [ ] Optimizar qué corre en cloud y qué en edge a partir de telemetría real.

**Entregable:** conjunto de tareas nuevas y métricas comparables, no sólo demostraciones aisladas.

---

## 8. Métricas y pruebas de aceptación

| Métrica | Cómo se mide |
|---|---|
| Éxito de detección | Objetos correctamente localizados sobre dataset etiquetado |
| Error de pose 3D | Diferencia posición/orientación respecto de referencia |
| Navegación | Error final respecto a pose objetivo y colisiones |
| Pick-and-place | Éxitos / intentos; posición final; caída del objeto |
| Latencia | Cámara → inferencia → comando → confirmación |
| Fiabilidad de nube | Timeouts, jitter, reconexiones y degradación |
| Seguridad | Violaciones de límites, activaciones de watchdog/parada |
| Robustez | Cambios de objetos, iluminación y posiciones |

Registrar siempre versión de código, checkpoint, configuración, hardware, fecha, escenario y resultado. Comparar cada versión VLA con una línea base determinística.

---

## 9. Estructura sugerida del repositorio

```text
g1-embodied-ai/
├── docs/
│   ├── hardware.md
│   ├── interfaces.md
│   ├── frames_tf.md
│   ├── safety.md
│   └── experiments.md
├── ros2_ws/src/
│   ├── g1_bringup/
│   ├── g1_robot_state_bridge/
│   ├── g1_hand_bridge/            # envolver control BrainCo existente
│   ├── g1_arm_bridge/             # envolver control articular existente
│   ├── g1_navigation_bridge/      # interfaz segura PC1
│   ├── g1_perception/
│   ├── g1_motion_planning/
│   ├── g1_action_adapter/
│   ├── g1_safety_supervisor/
│   └── g1_task_orchestrator/
├── cloud/
│   ├── vlm_server/
│   ├── vla_server/
│   └── containers/
├── learning/
│   ├── data_capture/
│   ├── datasets/
│   ├── training/
│   └── evaluations/
└── simulations/
```

**Nota:** estructura de referencia; adaptar los nombres a los paquetes ya existentes en el dev container, no duplicarlos.

---

## 10. Dependencias, riesgos y decisiones pendientes

1. **Nombre exacto de Qwen VL:** verificar si es Qwen3-VL-4B u otro checkpoint.
2. **Sensores 3D:** confirmar si el G1 entrega profundidad utilizable y qué frames están disponibles.
3. **Locomoción:** identificar interfaz externa de PC1 para objetivos de velocidad/poses, capacidades y límites.
4. **Control existente:** inventariar contratos de actuadores manuales y la disponibilidad de telemetría.
5. **Manos:** confirmar lectura de fuerza/tacto, unidades y modos soportados por los drivers instalados.
6. **Simulación:** elegir modelo actualizado del robot con las manos BrainCo.
7. **Cloud:** región de menor RTT real, costos de VRAM y estabilidad, privacidad y resiliencia.
8. **VLA:** elegir observaciones/frecuencia/vector de acciones a partir de las interfaces reales, no al revés.
9. **Audio:** tema aparcado (AudioHub → Whisper; Piper TTS): diagnosticarlo después, de forma independiente del roadmap motor.

---

## 11. Próximo sprint recomendado: integrar, no reescribir

**Objetivo del sprint:** construir la primera API segura de manipulación sobre las capacidades manuales que ya funcionan.

- [ ] Documentar cómo se envía actualmente una orden manual al brazo y cómo se obtiene confirmación.
- [ ] Documentar cómo se envía actualmente una orden manual a Revo 2 Touch y cómo se obtiene feedback.
- [ ] Comprobar estado articular continuo y frames TF.
- [ ] Crear un `Action Server` ROS 2 para alcanzar una pose conocida, con cancelación y timeout.
- [ ] Crear un `Action Server` para abrir/cerrar la mano con límites y confirmación.
- [ ] Encadenar **reach → grasp → lift → place** con el robot estacionario y PC1 activo.
- [ ] Loguear todos los ensayos antes de introducir comandos generados por VLA.

**Definición de terminado:** una secuencia física reproducible y supervisada que utiliza exclusivamente los controladores de bajo nivel ya disponibles; PC1 sigue gobernando equilibrio y piernas.

---

## 12. Referencias técnicas

- [Unitree SDK2](https://github.com/unitreerobotics/unitree_sdk2)
- [Unitree ROS 2](https://github.com/unitreerobotics/unitree_ros2)
- [BrainCo: integración G1 / Revo2](https://github.com/BrainCoTech/unitree-g1-brainco-hand)
- [BrainCo / Unitree XR Teleoperation](https://github.com/unitreerobotics/xr_teleoperate)
- [MoveIt 2](https://moveit.picknik.ai/)
- [Nav2](https://navigation.ros.org/)
- [Hugging Face LeRobot](https://github.com/huggingface/lerobot)
- [Physical Intelligence OpenPI](https://github.com/Physical-Intelligence/openpi)
- [NVIDIA Isaac GR00T](https://github.com/NVIDIA/Isaac-GR00T)
- [RunPod](https://www.runpod.io/)

> **Estado de este documento:** roadmap de ingeniería y arquitectura propuesta. Las integraciones, APIs, drivers, especificaciones de modelos y compatibilidades deben validarse contra las versiones efectivamente instaladas antes de aplicarse al robot físico.
