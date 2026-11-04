#!/usr/bin/env python3
"""Dry GR00T test, pod half: run a checkpoint on our G1 snapshots. Prints, moves nothing.

  python groot_dry_pod.py --model-path /workspace/runs/r10k/checkpoint-10000 --snaps /workspace/dry/snaps

Per snapshot, K samples of the same observation (flow-matching noise), and reports:
  * where the state falls against the checkpoint's own q01..q99 (out-of-distribution dims);
  * the chunk's first and last step (16 steps = 0.53 s at 30 Hz) minus the current state;
  * the largest step-to-step jump inside the chunk and the spread across the K samples.
"""
import argparse
import glob
import importlib
import json
import os
import sys

import cv2
import numpy as np
import torch

from gr00t.data.embodiment_tags import EmbodimentTag
from gr00t.policy.gr00t_policy import Gr00tPolicy

PARTS = {"left_arm": slice(0, 7), "right_arm": slice(7, 14),
         "left_hand": slice(14, 20), "right_hand": slice(20, 26)}
TASK = "Pick up the red cup on the table."


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model-path", required=True)
    ap.add_argument("--snaps", required=True)
    ap.add_argument("--config", default="/workspace/code/g1_brainco_config.py", help="empty = none")
    ap.add_argument("--task", default=TASK)
    ap.add_argument("--k", type=int, default=3)
    ap.add_argument("--report", default="report.json")
    a = ap.parse_args()

    if a.config:
        sys.path.append(os.path.dirname(a.config))
        importlib.import_module(os.path.splitext(os.path.basename(a.config))[0])
    tag = EmbodimentTag.resolve("new_embodiment")
    policy = Gr00tPolicy(embodiment_tag=tag, model_path=a.model_path, device="cuda")
    mc = policy.get_modality_config()
    stats = policy.processor.state_action_processor.statistics[tag.value]
    vkey = mc["video"].modality_keys[0]
    lkey = mc["language"].modality_keys[0]
    # Every checkpoint we use lays the 26 numbers out the same way (Unitree's datasets: left arm,
    # right arm, left hand, right hand); only the key names and how they are split differ.
    dims, start = {}, 0
    for k in mc["state"].modality_keys:
        n = len(stats["state"][k]["q01"])
        dims[k] = slice(start, start + n)
        start += n
    assert start == 26, f"state is {start}-D, expected 26: {dims}"
    q01 = np.concatenate([stats["state"][k]["q01"] for k in mc["state"].modality_keys])
    q99 = np.concatenate([stats["state"][k]["q99"] for k in mc["state"].modality_keys])
    print("keys", vkey, list(dims), mc["action"].modality_keys)
    np.set_printoptions(precision=2, suppress=True, linewidth=160)

    report = []
    for jf in sorted(glob.glob(os.path.join(a.snaps, "[0-9]*.json")), key=lambda p: int(os.path.basename(p)[:-5])):
        i = os.path.basename(jf)[:-5]
        s = np.array(json.load(open(jf))["state"], dtype=np.float32)
        img = cv2.cvtColor(cv2.imread(os.path.join(a.snaps, f"{i}.jpg")), cv2.COLOR_BGR2RGB)
        for task in a.task.split("|"):
            obs = {"video": {vkey: np.stack([img[None]] * a.k)},
                   "state": {k: np.stack([s[v][None]] * a.k) for k, v in dims.items()},
                   "language": {lkey: [[task]] * a.k}}
            torch.manual_seed(0)
            action, _ = policy.get_action(obs)
            chunk = np.concatenate([action[k] for k in mc["action"].modality_keys], axis=-1)  # (K, 16, 26)
            print(f"\n=== snapshot {i} | {task}")
            rep = {"snap": i, "task": task, "groups": {}}
            for k, v in PARTS.items():
                ood = [j for j in range(v.start, v.stop) if not (q01[j] <= s[j] <= q99[j])]
                first = chunk[0, 0, v] - s[v]
                last = chunk[0, -1, v] - s[v]
                jump = np.abs(np.diff(chunk[0, :, v], axis=0)).max()
                spread = chunk[:, :, v].std(axis=0).mean()
                print(f"{k:10s} state {s[v]}  out-of-range dims {ood}")
                print(f"{'':10s} step0-state {first}  step15-state {last}")
                print(f"{'':10s} max step jump {jump:.3f}  spread over {a.k} samples {spread:.3f}")
                rep["groups"][k] = {"ood": ood, "first": first.tolist(), "last": last.tolist(),
                                    "jump": float(jump), "spread": float(spread)}
            report.append(rep)
    json.dump(report, open(os.path.join(a.snaps, a.report), "w"), indent=1)
    print("\nDRY_DONE")


if __name__ == "__main__":
    main()
