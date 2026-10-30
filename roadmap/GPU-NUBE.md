# GPU en la nube (RunPod) — plan de uso

**Escrito el 2026-10-30.** Lecturas del día (MCP de RunPod: `list-gpu-types`, `list-data-centers`,
`list-pods`, `get-ssh-keys`) y documentación de RunPod. Nada creado todavía salvo la clave SSH.
Sirve a dos cosas: el VLM de Pilot (§7) y GR00T (`G1-GROOT.md` paso 1).

## 0. Estado de la cuenta (2026-10-30)

- Plugin `runpod@runpod` + MCP por OAuth en Claude Code, firmado con la **cuenta personal** del
  usuario: 0 pods, 0 volúmenes, 0 endpoints, sin crédito, y `get-organization` responde
  *"Organizations are not enabled for this user"* (no está en ningún equipo).
- Clave SSH propia `~/.ssh/runpod_ed25519` ("ia-pc->runpod"), registrada como única de la
  cuenta. La de `id_ed25519` es la del robot: no se mezclan.
- ✅ **Resuelto 2026-10-30 13:54:** el MCP ahora actúa sobre el equipo del jefe ("fermaura@gmail.com's Team", rol dev, $100 vistos en la consola, aviso de saldo bajo en $5, sin autopago, tope $80/h) y la clave SSH está registrada ahí. Lo de abajo queda como explicación.
- **El crédito es por cuenta.** Si el jefe cargó en la suya, hay que usar **su** cuenta como
  equipo: él la convierte en *Team* (consola → Team), invita al usuario con rol **dev**, el
  usuario acepta y elige el equipo arriba a la izquierda. Ahí se crea una **API key del
  equipo** (restringida, ver §6) y con ella se reconecta el MCP y anda el controlador de §3.
  Firmando el MCP por OAuth con la cuenta personal se sigue viendo una cuenta vacía.

## 1. Forma: pods efímeros + un volumen de red que no se borra

- **Volumen de red** (persistente, vive en UN datacenter): pesos de modelos, datasets de
  teleop, checkpoints, venvs, estado de Tailscale. Se cobra por GB-hora reservado, con o sin
  pod. Solo crece: empezar en **100 GB**.
- **El pod no se "para", se borra.** Un pod parado queda atado a su máquina y al volver puede
  no tener GPU (otro la tomó). Con todo lo valioso en el volumen, prender = **crear** un pod
  nuevo en el mismo datacenter con el volumen en `/workspace`, y apagar = **borrarlo**. Así no
  queda disco cobrando y nunca hay un pod con cero GPUs.
- Los volúmenes **solo se montan en Secure Cloud**: los precios que cuentan son los *secure*.
- **Imagen fija por digest**, no por `:latest`. El arranque (`start.sh`) vive en un repo
  nuestro y el pod lo trae con `git pull` a `/workspace`, como al robot.
- **Arranque en frío** = bajar la imagen + cargar el modelo desde el volumen. Hay que medirlo
  (meta: menos de 3 min). Si el datacenter ofrece volumen `HIGH_PERFORMANCE` (3× de
  rendimiento), usarlo para que la carga sea rápida.

## 2. Dónde: no hay datacenter en Sudamérica

`list-data-centers` con `SOUTH_AMERICA` no devolvió ninguno: lo más cerca es el este de
EE. UU. o Canadá. El volumen fija el datacenter para siempre, así que hay que elegirlo antes y
medirlo. Tiene que tener **volumen de red + una GPU de 48 GB + H100 para el ajuste fino**,
todo en el mismo lugar.

| Datacenter | Volumen | GPUs con stock hoy (lectura del 30-10) | Comentario |
|---|---|---|---|
| **CA-MTL-1** (Montreal) | HIGH_PERFORMANCE | A40, H100 SXM | El mejor candidato: tiene las dos GPUs y un volumen rápido |
| US-NE-1 | STANDARD | PRO 6000 MIG 48 GB, H100 SXM, B200 | Alternativa |
| US-NC-1 | STANDARD | solo H200 | No hay una GPU de 48 GB |
| US-WA-1 | STANDARD | RTX 6000 Ada, A100 | Costa oeste: más lejos |
| US-GA-2, US-MD-1, US-TX-4 | **sin volumen** | — | Descartados |

**✅ Medido 2026-10-30 14:04-14:08** desde la PC (oficina), las dos al mismo tiempo. Se midió el
tiempo de conexión TCP al SSH del pod, 3 min, una cada 0.5 s, y ping:

| | TCP p50 | p90 | p99 | máx | ping |
|---|---|---|---|---|---|
| **CA-MTL-1** (A40) | **176 ms** | 188 | 437 | 1233 | bloqueado (ICMP filtrado; TCP sin fallas) |
| US-NE-1 (CPU) | 192 ms | 204 | 279 | 353 | 177.8 ms promedio, 0 % de pérdida en 800 |

- Las colas de más de 1 s son por armar la conexión del lado de RunPod: el ping en esa misma
  ventana no perdió nada. Una conexión persistente (ZMQ, Tailscale) no las paga. Hay que
  volver a medir con la conexión real.
- **El primer pod A40 en CA-MTL-1 nunca levantó el contenedor** ("container not found" a los 7
  min); el segundo arrancó en ~2 min. Hay que tenerlo en cuenta para el arranque en frío.
- Para el presupuesto de §5: con ~180 ms de ida y vuelta, **8 pasos (267 ms) no entra**;
  16 pasos (533 ms, 70 % = 373 ms) deja ~190 ms para la inferencia y el resto.
- **Elegido: CA-MTL-1.** Es un poco más rápido, tiene el volumen rápido y es más barato: A40 a
  $0.59/h contra la PRO 6000 MIG 48 GB de US-NE-1 a $1.29/h (US-NE-1 no tiene A40).
- Costo de la prueba: unos $0.14 (3 pods de 5-13 min cada uno); la facturación del día todavía
  no lo mostraba.

**Medir antes de crear el volumen:** un pod de CPU barato unos minutos en CA-MTL-1 y en
US-NE-1, ida y vuelta por Tailscale desde la PC **y desde la red de los robots**, p50/p99 en
5 minutos. Se elige con el p99, no con el promedio.

## 3. Que se prenda y se apague solo

Hay **dos guardias de apagado**, una adentro del pod y otra en la PC, para que ninguna sola
pueda dejar la GPU cobrando:

**Prender** — un controlador chico en la PC (`cloud_gpu`, en AI-VL-ecosystem, con la API key
del equipo en un archivo `0600` fuera de los repos):
- `up`: crea el pod desde la plantilla (GPU, datacenter, volumen, secretos) y espera a que
  responda la salud por Tailscale, no a que diga "Running".
- Disparadores: el botón en Pilot (Settings → "GPU en la nube"), la orden por línea de
  comando y, opcional, un horario (por ejemplo, días hábiles de 9 a 18).
- **Bajo demanda:** si iacore no encuentra el VLM de la nube, contesta con el local de la
  5060 (que sigue levantado) y pide `up`. Así nunca hay que esperar el arranque en frío.

**Apagar** —
- **Adentro del pod:** un watchdog mira los contadores de llama-server (`--metrics`) y la
  última petición a GR00T. Si pasan **20 min** sin uso, se para solo con la `RUNPOD_API_KEY`
  propia del pod (`runpodctl pod stop $RUNPOD_POD_ID`). Esto funciona aunque la PC esté
  apagada.
- **Desde la PC:** cada 5 min el controlador **borra** los pods parados que creó él. Además
  aplica un **tope duro** (por ejemplo, 10 h por día y apagado a las 20:00) y le avisa a
  Pilot.
- Pods que no creó el controlador (como el de ajuste fino) no se tocan: se informan.

**Ajuste fino** (H100, $3.99/h *secure*): es otro pod en el mismo datacenter y con el mismo
volumen. Se lanza a mano y se borra solo al terminar el entrenamiento (`trap` al final del
script), con un tope de horas. **No** levanta Tailscale con el estado del pod de inferencia,
porque dos nodos con la misma identidad se pisan.

## 4. Red: nada abierto a internet

- **Tailscale adentro del pod** en modo `--tun=userspace-networking` (el contenedor no trae
  `/dev/net/tun`). En ese modo las conexiones que entran por la IP del tailnet llegan a los
  servicios del pod en `localhost`, que es lo único que necesitamos.
- El estado de Tailscale se guarda en `/workspace/tailscale/`: cada pod nuevo vuelve con **el
  mismo nombre y la misma IP del tailnet**, y nada de lo que apunta a él cambia.
- El primer alta usa una *auth key* guardada como **secreto de RunPod**, con la etiqueta
  `tag:gpu-cloud`.
- **ACL:** solo la PC (y el cliente del G1, ver abajo) llegan a `tag:gpu-cloud` en
  `:8081` (llama-server) y `:5555` (ZMQ de GR00T). `tag:gpu-cloud` no puede iniciar nada
  hacia el tailnet, así que un pod comprometido no ve la red de la oficina.
- **Puertos públicos del pod: ninguno** salvo `22/tcp` para recuperarlo, solo con clave. La
  autenticación de las aplicaciones va igual: `--api-key` en llama-server y `api_token` en
  GR00T, los dos como secretos de RunPod.
- **Dónde corre el cliente de GR00T (falta decidirlo):**
  - **(a) En la PC.** Ya está en el tailnet, ya tiene los cuadros y el estado, y le manda los
    trozos de acción al relay. **Recomendado:** no hay que instalar nada en el robot.
  - **(b) En la PC2 del G1.** Hay que instalar Tailscale en el robot, que es un cambio de
    sistema y no entra por `git pull`.

## 5. Latencia: el presupuesto de GR00T

El cliente pide un trozo de acciones y ejecuta 8-16 pasos a 30 Hz mientras pide el siguiente:
eso da **267-533 ms** de margen. En ese margen tienen que entrar la ida y vuelta, la inferencia
en el pod, codificar el cuadro y, en (a), el salto PC → relay por el Wi-Fi del robot.

- **Medir antes de los 20 intentos,** con el modelo real cargado y con cuadros y estados
  reales: p50/p99 de punta a punta, 10 min seguidos y con el robot en su red de siempre.
- **Regla:** p99 < 70 % del margen del trozo que se use. Si 8 pasos no entra, usar 16.
- **Si un trozo llega tarde:** mantener la última pose, nunca extrapolar. Con **dos tardes
  seguidos se para** y el dead-man queda armado. El brazo sigue con las reglas de
  `G1-GROOT.md` §5: rampa de peso, velocidad reducida y operador con el control.
- **El plan del jefe del 21-10 ya no manda acá.** El usuario aclaró el 2026-10-30 que ese
  plan es viejo y que lo combinaron con él: GR00T se sirve desde la nube y el lazo cierra por
  Tailscale. Lo que protege al robot son las guardias de arriba y las de `G1-GROOT.md` §5.

## 6. Plata y secretos

- **API key restringida** del equipo, solo con lo que usa el controlador (pods, lectura). Va
  en el archivo `0600`, nunca en un repo ni en el chat.
- **Secretos en RunPod Secrets** (`{{ RUNPOD_SECRET_… }}`): la auth key de Tailscale, la
  `--api-key` del VLM, el `api_token` de GR00T y el token de HF.
- **Aviso de saldo bajo activado.** Con saldo en $0, RunPod para todos los pods, y si el
  volumen no se puede pagar **lo borra sin vuelta**. Por eso:
  - los datasets de teleop y los checkpoints buenos se copian también a la PC (por la API S3
    del volumen o con `runpodctl send`);
  - el volumen no es el único lugar donde viven.
- **Costos** (lectura del 30-10, *secure*): A40 $0.59/h, RTX 6000 Ada $0.99/h, L40S $1.09/h,
  H100 SXM $3.99/h. Con 8 h por día hábil, una A40 sale ~$104 por mes. Hay que sumarle el
  volumen, cuyo precio por GB se lee al crearlo. Un ajuste fino de 3-4 h en H100 sale
  ~$12-16.
- **Reporte semanal** del gasto con `list-billing` (el mismo dato del MCP), para que nadie se
  entere por el saldo.

## 6b. Medido: el VLM de 8B en la nube contra el de 4B local (2026-10-30)

Los dos con el mismo código y el mismo día. El 8B en un A40 de CA-MTL-1 (llama.cpp b11701,
`-np 3`, por un túnel SSH); el 4B Q4 en la 5060 de la PC.

| | 4B local | 8B nube |
|---|---|---|
| Lectura (`vlm_reading_check`, 171 respuestas) | **91 %** (155) | 89 % (152, una por corte de conexión) |
| Charla (`vlm_chat_check`, 93) | 75 % | **80 %** |
| Primera palabra, pregunta sola | **0.67 s** | 2.25 s |
| Respuesta entera | **0.75 s** | 3.7 s |

- **Lectura:** el 8B no lee mejor. Falla en otras cosas (temperatura del 17, prensaestopas,
  interruptores rojos).
- **Charla:** el 8B gana en `ends_asking` (92 % contra 85), `expect` (98 contra 91) y
  `repeats`. Pierde en `acting` (92 % contra 100: usa **negritas** con asteriscos) y
  `greeting` (abre con "¡Hola!").
- **Es más charlatán:** responde con más palabras, y por eso la respuesta entera tarda más.
- **De dónde salen los 2.25 s:**
  - ~0.8 s en el servidor (imagen + prompt; ojo, el encoder **sí** está en la GPU, no es lo
    de Ollama);
  - ~0.4 s de la ida y vuelta del clasificador previo (el banco lo llama en serie; en la app
    va en paralelo);
  - ~1 s de **subir la foto**.

  La oficina sube a 3.5-4 Mbps (Cloudflare: 440-510 KB/s; baja a 20 Mbps). Por el túnel
  hasta Montreal salieron 150-190 KB/s, y una foto pesa 72 KB de mediana (hasta 218 KB).
  Mandarla a 768 px no cambió nada medible.
- **Conclusión: por ahora no conviene pasar Pilot al 8B en la nube.** No lee mejor, charla un
  poco mejor y tarda 3-4 veces más. La nube vale para GR00T, y para el VLM recién si hace
  falta un modelo que lea mejor (probar otro, no solo uno más grande) o si la subida de la
  oficina mejora.
- Resultados: `AI-VL-core/results/vlm_reading_check_g1_20261030_11{3859,4814}.json` y
  `vlm_chat_check_{4b-local,8b-cloud}_*.json`.
- Costo: unos $0.20 entre todas las pruebas del día (saldo $99.81 a las 14:50).

## 6c. Medido: fotos de campo, y la generación nueva (2026-10-30, tarde)

El banco fácil (fotos de catálogo) no separaba los modelos. Armé uno de **fotos de campo**: 24
fotos reales de Wikimedia Commons (medidores en paredes, pinzas en uso, tableros sucios,
chapas de motor), con **50 preguntas cuyas respuestas anoté mirando cada foto ANTES de correr
ningún modelo**. Saqué una pregunta ambigua y ensanché un regex demasiado estricto, y volví a
puntuar a todos con el mismo criterio. Está en el scratchpad de la sesión: `hardbench/`
(`cases.py`, `run.py`, `rescore.py`, `commons/index.json` con la licencia de cada foto).
Falta pasarlo al repo.

| Modelo | Campo | Fácil | Charla | 1.ª palabra | Dónde |
|---|---|---|---|---|---|
| Qwen3-VL-4B Q4 (el de hoy) | 87 % | 91 % | 75 % | 0.66 s | 5060 |
| Qwen3-VL-8B Q8 | 93 % | 89 % | 80 % | 3.6 s | A40, nube |
| Qwen3.6-35B-A3B Q4 | 95 % | — | — | 2.7 s (~1 s en el servidor, ~100 tok/s) | A40, nube |
| **Qwen3.5-4B Q4** (mar 2026) | **96 %** | 88 % | 65 % | 0.82 s | **5060, gratis** |

- Qwen3.5/3.6 entienden imágenes aunque el nombre no diga "VL". **Piensan por defecto**: hay que
  correrlos con `--jinja --chat-template-kwargs '{"enable_thinking":false}'`. Así no hubo
  pensamiento oculto: 19-21 tokens por respuesta.
- La tabla oficial de la tarjeta de Qwen3.5-4B (con pensamiento) lo pone a la par o por encima
  del Qwen3-VL-30B-A3B: RealWorldQA 79.5 contra 77.4, OCRBench 85.0 contra 83.9, CountBench 96.3
  contra 90.0.
- **Conclusión:** para el VLM de Pilot no hace falta la nube. **El Qwen3.5-4B en la 5060 lee
  mejor que todo lo probado y es gratis.**
- **Para pasarlo falta retocar el prompt de la charla:** `on_topic` baja de 90 % a 65 % (a un
  comentario o un saludo le describe el cuadro) y usa algún emoji más. Se mide con los dos
  bancos, como el 28-10. El archivo ya está en `AI-VL-core/vlm_models/Qwen3.5-4B-Q4_K_M.gguf` +
  `mmproj-Qwen3.5-4B-F16.gguf`. `linux/vlm-server.sh` todavía no pasa el
  `--chat-template-kwargs`.
- La nube queda para **GR00T**. En el volumen ya están el código n1.7 + el entorno
  (`/workspace/envs/gr00t`, torch 2.7.1+cu128, ve la A40) y los datasets
  `G1_Brainco_PickDrink` (201 demos, 6.4 GB) y `G1_Brainco_PickApple` (Apache-2.0): **datos de
  G1 con nuestras manos BrainCo**, que reemplazan al ApplePnP de Dex3 para el paso 1A/5.
- Gasto del día: ~$1.10 en pods, más el volumen.

## 6d. GR00T con datos de G1 + BrainCo (2026-10-30)

- `G1_Brainco_PickDrink` está convertido de LeRobot v3 a v2 (el script del repo tardó 2 min), en
  `/workspace/datasets/lerobot/unitreerobotics/G1_Brainco_PickDrink_Dataset`. La copia v3 quedó
  como `*_v30`.
- Tiene `meta/modality.json` con:
  - **una sola cámara**, `ego_view` = `cam_left_high` de la cabeza, para que se parezca a
    nuestro robot (el dataset trae 4: dos en la cabeza y dos en las muñecas);
  - estado y acción de 26 = 7 + 7 brazos (el mismo orden que nuestro `q[15:29]`) + 6 + 6 dedos.
- Config: `/workspace/code/g1_brainco_config.py` (`NEW_EMBODIMENT`). Los brazos van RELATIVOS
  y los dedos ABSOLUTOS; 16 pasos.
- **Bloqueado:** el backbone de N1.7 es `nvidia/Cosmos-Reason2-2B`, **gated** en Hugging Face
  (`gated=auto`: se aprueba solo al aceptar la licencia). El usuario tiene que aceptar la
  licencia, crear un token Read y guardarlo como secreto de RunPod **`hf_token`**; el pod lo
  recibe como `HF_TOKEN`.
- Después: el ajuste de prueba (50 pasos, `/workspace/groot_prep.sh` lo retoma donde quedó)
  para medir la velocidad A40 vs H100. Luego el seco: el open-loop sobre episodios no vistos y
  los cuadros de nuestro robot.

## 7. Orden de trabajo

1. [ ] **Cuenta:** confirmar dónde está el crédito; si es del jefe, armar el equipo + rol dev +
   API key restringida (§0). Activar el aviso de saldo bajo.
2. [ ] **Tailscale:** etiqueta `tag:gpu-cloud`, ACL y auth key reutilizable con etiqueta → secreto
   de RunPod.
3. [x] ✅ 2026-10-30 **Medir la ida y vuelta** a CA-MTL-1 y US-NE-1 con un pod de CPU (§2) → elegir el
   datacenter.
4. [~] ✅ 2026-10-30 volumen creado desde la consola: `3l08i2rln0` ("then_green_spider"), CA-MTL-1, 100 GB, HIGH_PERFORMANCE, **$14/mes** ($0.14/GB, el doble del estándar), se cobra aunque no haya pod. ✅ **Modelos bajados 2026-10-30 14:24** con un A40 de ~5 min (bajó 28 GB en menos de 1 min): `/workspace/models/vlm/` (Qwen3VL-8B-Instruct-Q8_0.gguf 8.2 G + mmproj F16 1.1 G), `/workspace/models/groot/GR00T-N1.7-3B` (6.5 G, checkpoint normal en safetensors, para el ajuste fino) y `/workspace/models/groot/GR00T-N1.7-ApplePnP-V1` (12 G). **Ojo:** ApplePnP viene **exportado en ONNX** para ONNX Runtime/TensorRT (`exported_leapp.yaml`: entra `ego_view` 480×640 + estado por partes, incluidas las piernas), no como checkpoint: el paso 1A se corre con ONNX Runtime, no con `run_gr00t_server.py`. Script: `/workspace/fetch_models.sh`, que se puede volver a correr.
   N1.7.
5. [ ] **`start.sh` + watchdog** en el repo; pod de A40 a mano; medir el arranque en frío y la
   ida y vuelta real.
6. [ ] **iacore:** VLM de la nube primero y el local de respaldo (`VLM_URL` con salud), con
   `-np 3` en la nube. Correr los dos bancos (`vlm_reading_check`, `vlm_chat_check`) contra el
   modelo grande.
7. [ ] **El controlador `cloud_gpu`** (`up`/`down`/barrido/tope) + el botón en Pilot.
8. [ ] **GR00T paso 1A en seco** (`G1-GROOT.md`): cuadros y estados reales, acciones sin
   mandar. Medir el presupuesto de §5.
9. [ ] Movimiento con GR00T desde la nube, con las guardias de §5 y `G1-GROOT.md` §5.
