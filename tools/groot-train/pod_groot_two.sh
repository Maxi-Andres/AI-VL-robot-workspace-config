#!/usr/bin/env bash
# Runs ON a fresh pod (no network volume: Montreal has had no GPUs for two days): builds the
# GR00T N1.7 env, the G1+BrainCo PickDrink dataset as LeRobot v2 split train/val (20 episodes
# held out), then TWO separate fine-tunes, each in its own folder:
#   runs/pilot1500  1500 steps x 16  (measures speed and memory; a baseline)
#   runs/r10k       10000 steps x 16, a checkpoint every 2500
# Every step skips what is done, so it can be re-run. Logs: /workspace/logs/groot_two.log.
set -euo pipefail
W=/workspace
DS=unitreerobotics/G1_Brainco_PickDrink_Dataset
ROOT=$W/datasets/lerobot
SPLIT=$W/datasets/pickdrink_split
mkdir -p "$W/code" "$W/envs" "$ROOT/unitreerobotics" "$W/hf" "$W/models/groot" "$W/runs" "$W/logs"
export HF_HOME="$W/hf" HF_HUB_ENABLE_HF_TRANSFER=1 PATH="$HOME/.local/bin:/usr/local/cuda/bin:$PATH"
export CUDA_HOME="${CUDA_HOME:-/usr/local/cuda}"
# The gated backbone (nvidia/Cosmos-Reason2-2B) needs the token: a RunPod secret that reaches
# only PID 1's environment, not an SSH-launched shell.
export $(tr "\0" "\n" < /proc/1/environ | grep "^HF_TOKEN=" | xargs)
stamp() { echo "$(date -u +%H:%M:%S) $*"; }

# 1. Downloads in the background while the code and its env install.
python3 -m pip install -q --break-system-packages -U "huggingface_hub[cli]" hf_transfer
(
    [ -f "$ROOT/$DS/meta/info.json" ] || hf download "$DS" --repo-type dataset --local-dir "$ROOT/$DS" >/dev/null
    [ -f "$W/models/groot/GR00T-N1.7-3B/config.json" ] ||
        hf download nvidia/GR00T-N1.7-3B --local-dir "$W/models/groot/GR00T-N1.7-3B" >/dev/null
    echo DOWNLOADS_DONE
) &
DL=$!

(command -v ffmpeg && command -v git-lfs) >/dev/null ||
    (apt-get update -qq && apt-get install -y -qq ffmpeg git-lfs >/dev/null)
command -v uv >/dev/null || curl -LsSf https://astral.sh/uv/install.sh | sh
[ -d "$W/code/Isaac-GR00T/.git" ] || git clone --depth 1 --branch n1.7-release \
    https://github.com/NVIDIA/Isaac-GR00T "$W/code/Isaac-GR00T"
cd "$W/code/Isaac-GR00T"
git lfs install --local >/dev/null && git lfs pull      # the prebuilt wheels uv sync needs
UV_PROJECT_ENVIRONMENT="$W/envs/gr00t" UV_LINK_MODE=copy uv sync --python 3.10
PY="$W/envs/gr00t/bin/python"
"$PY" -c "import torch, gr00t; print('torch', torch.__version__, torch.cuda.get_device_name(0))"
stamp ENV_DONE
wait $DL

# 2. v3 -> v2 (the converter keeps the v3 copy as *_v30), then how GR00T reads it: 26 floats =
#    7 left arm, 7 right arm, 6+6 fingers; one camera, the head's left eye, like our robot.
if ! grep -q '"v2' "$ROOT/$DS/meta/info.json"; then
    [ -x /root/lerobot-env/bin/python ] || { uv venv -q --python 3.10 /root/lerobot-env &&
        uv pip install -q --python /root/lerobot-env/bin/python "lerobot==0.4.0" jsonlines; }
    /root/lerobot-env/bin/python scripts/lerobot_conversion/convert_v3_to_v2.py \
        --repo-id "$DS" --root "$ROOT"
fi
cat > "$ROOT/$DS/meta/modality.json" <<'EOF'
{
  "state":  {"left_arm": {"start": 0, "end": 7}, "right_arm": {"start": 7, "end": 14},
             "left_hand": {"start": 14, "end": 20}, "right_hand": {"start": 20, "end": 26}},
  "action": {"left_arm": {"start": 0, "end": 7}, "right_arm": {"start": 7, "end": 14},
             "left_hand": {"start": 14, "end": 20}, "right_hand": {"start": 20, "end": 26}},
  "video":  {"ego_view": {"original_key": "observation.images.cam_left_high"}},
  "annotation": {"human.task_description": {"original_key": "task_index"}}
}
EOF
cat > "$W/code/g1_brainco_config.py" <<'EOF'
"""GR00T modality config for the G1 with BrainCo hands (Unitree's G1_Brainco_* datasets):
one head camera, arms as deltas from the current joints, fingers as absolute targets."""
from gr00t.configs.data.embodiment_configs import register_modality_config
from gr00t.data.embodiment_tags import EmbodimentTag
from gr00t.data.types import ActionConfig, ActionFormat, ActionRepresentation, ActionType, ModalityConfig

PARTS = ["left_arm", "right_arm", "left_hand", "right_hand"]
ARM = ActionConfig(rep=ActionRepresentation.RELATIVE, type=ActionType.NON_EEF, format=ActionFormat.DEFAULT)
HAND = ActionConfig(rep=ActionRepresentation.ABSOLUTE, type=ActionType.NON_EEF, format=ActionFormat.DEFAULT)

g1_brainco_config = {
    "video": ModalityConfig(delta_indices=[0], modality_keys=["ego_view"]),
    "state": ModalityConfig(delta_indices=[0], modality_keys=PARTS),
    "action": ModalityConfig(delta_indices=list(range(16)), modality_keys=PARTS,
                             action_configs=[ARM, ARM, HAND, HAND]),
    "language": ModalityConfig(delta_indices=[0], modality_keys=["annotation.human.task_description"]),
}
register_modality_config(g1_brainco_config, embodiment_tag=EmbodimentTag.NEW_EMBODIMENT)
EOF
# 20 episodes spread evenly over the dataset never reach training: the judge of overfitting.
[ -d "$SPLIT/val" ] || python3 "$W/tools/split_lerobot_v2.py" --src "$ROOT/$DS" --out "$SPLIT" --n-val 20
stamp DATA_DONE

# 3. The two runs. Same data, same settings; only the length differs.
# The GR00T env has no hf_transfer, and it downloads the gated backbone on first use.
unset HF_HUB_ENABLE_HF_TRANSFER
train() {   # name steps save_steps keep
    [ -d "$W/runs/$1/checkpoint-$2" ] && return 0
    stamp "TRAIN_START $1"
    "$PY" gr00t/experiment/launch_finetune.py \
        --base-model-path "$W/models/groot/GR00T-N1.7-3B" --dataset-path "$SPLIT/train" \
        --embodiment-tag NEW_EMBODIMENT --modality-config-path "$W/code/g1_brainco_config.py" \
        --num-gpus 1 --output-dir "$W/runs/$1" --max-steps "$2" --save-steps "$3" \
        --save-total-limit "$4" --global-batch-size 16 --dataloader-num-workers 12
    stamp "TRAIN_DONE $1"
}
train pilot1500 1500 1500 1
train r10k 10000 2500 4
stamp ALL_DONE
