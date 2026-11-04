#!/usr/bin/env python3
"""Imagined rollout: chain N chunks (16 steps each, 0.53 s) feeding the policy's own last action
back as the next state, with the image FIXED. Moves nothing. Answers "where would the arm head
in ~5 s from this frame?" — not whether it would succeed (the scene never changes here).

  python groot_rollout_pod.py --model-path M --config M/modality_config.py --snaps DIR --ids 0,2 --task "..."
"""
import argparse
import importlib
import json
import os
import sys

import cv2
import numpy as np
import torch

from gr00t.data.embodiment_tags import EmbodimentTag
from gr00t.policy.gr00t_policy import Gr00tPolicy

NAMES = ["sh_pitch", "sh_roll", "sh_yaw", "elbow", "wr_roll", "wr_pitch", "wr_yaw"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model-path", required=True)
    ap.add_argument("--config", default="")
    ap.add_argument("--snaps", required=True)
    ap.add_argument("--ids", default="0")
    ap.add_argument("--task", required=True)
    ap.add_argument("--chunks", type=int, default=10)
    a = ap.parse_args()
    if a.config:
        sys.path.append(os.path.dirname(a.config))
        importlib.import_module(os.path.splitext(os.path.basename(a.config))[0])
    tag = EmbodimentTag.resolve("new_embodiment")
    policy = Gr00tPolicy(embodiment_tag=tag, model_path=a.model_path, device="cuda")
    mc = policy.get_modality_config()
    stats = policy.processor.state_action_processor.statistics[tag.value]
    vkey, lkey = mc["video"].modality_keys[0], mc["language"].modality_keys[0]
    dims, start = {}, 0
    for k in mc["state"].modality_keys:
        n = len(stats["state"][k]["q01"])
        dims[k] = slice(start, start + n)
        start += n
    out = {}
    for i in a.ids.split(","):
        s0 = np.array(json.load(open(f"{a.snaps}/{i}.json"))["state"], dtype=np.float32)
        img = cv2.cvtColor(cv2.imread(f"{a.snaps}/{i}.jpg"), cv2.COLOR_BGR2RGB)
        s = s0.copy()
        traj = []
        for c in range(a.chunks):
            obs = {"video": {vkey: img[None, None]},
                   "state": {k: s[v][None, None] for k, v in dims.items()},
                   "language": {lkey: [[a.task]]}}
            torch.manual_seed(c)
            action, _ = policy.get_action(obs)
            chunk = np.concatenate([action[k] for k in mc["action"].modality_keys], axis=-1)[0]
            s = chunk[-1].astype(np.float32)
            traj.append((s - s0).tolist())
        d = np.array(traj)
        print(f"\n=== snap {i} | {a.task}  (change from start, rad / hand 0-1)")
        for t in (1, 4, 9):
            if t < len(d):
                print(f"t={0.53 * (t + 1):.1f}s  L {np.round(d[t, 0:7], 2)}  R {np.round(d[t, 7:14], 2)}"
                      f"  handL {np.round(d[t, 14:20], 2)}  handR {np.round(d[t, 20:26], 2)}")
        out[i] = traj
    json.dump(out, open(f"{a.snaps}/rollout.json", "w"))
    print("\nROLLOUT_DONE")


if __name__ == "__main__":
    main()
