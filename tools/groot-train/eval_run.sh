#!/usr/bin/env bash
# eval_run.sh <checkpoint dir> <name>: the held-out open-loop eval on all 20 val episodes.
set -euo pipefail
cd /workspace/code/Isaac-GR00T
export HF_HOME=/workspace/hf $(tr "\0" "\n" < /proc/1/environ | grep "^HF_TOKEN=" | xargs)
/workspace/envs/gr00t/bin/python /workspace/tools/eval_heldout.py --model-path "$1" \
    --dataset-path /workspace/datasets/pickdrink_split/val \
    --modality-config-path /workspace/code/g1_brainco_config.py \
    --traj-ids $(seq 0 19) --json-out "/workspace/evals/$2.json"
echo "EVAL_DONE $2"
