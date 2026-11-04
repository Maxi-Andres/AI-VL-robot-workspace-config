# GR00T dry tests on our G1 (nothing is ever sent to the robot)

Used on 2026-11-04 (`roadmap/GPU-NUBE.md` §6f). The pod has no port forward through the
`ssh.runpod.io` proxy, so the loop is offline: snapshots here, policy there.

1. `groot_snap.py` (this PC, AI-VL-core venv for OpenCV): N head frames from `rtsp://…/g1` +
   26-D state (arms q[15:29], BrainCo pos/1000) from the executor's joint stream.
2. Copy the folder to the pod (base64 through the SSH session works; `ssh.direct` allows scp).
3. `groot_dry_pod.py`: one chunk per snapshot and instruction (`--task "a|b|c"`), K samples:
   motion vs state, step jump, spread, dims outside the checkpoint's q01..q99. Works with any
   26-D checkpoint (key names are read from the model).
4. `make_cross.py`: image × state swaps against a held-out dataset episode (AV1 → torchcodec).
5. `groot_rollout_pod.py`: chains N chunks with the image fixed — where the arm would head.
