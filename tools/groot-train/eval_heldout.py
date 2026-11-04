#!/usr/bin/env python3
"""Held-out open-loop evaluation for GR00T N1.7 checkpoints, with smoothness metrics.

Same protocol as gr00t/eval/open_loop_eval.py at n1.7-release (one inference every
`action_horizon` steps, ground-truth state and image at that step, the predicted chunk
laid end to end), plus what that script does not report:

  * per-group MAE (left_arm, right_arm, left_hand, right_hand) instead of one number that
    mixes radians with [0,1] hand units, and a range-normalised MAE (divided by the
    per-dimension q99-q01 of the checkpoint's own training statistics);
  * smoothness: mean |a[t+1]-a[t]| INSIDE predicted chunks vs the same on ground truth,
    and the jump at chunk boundaries (expected to be larger: each chunk is a new sample);
  * sampling spread: the same observation is run K times in one batch and the std across
    the K samples is reported (flow-matching noise);
  * --denoising-steps really takes effect here (open_loop_eval.py parses it but never
    passes it to the model); it overrides action_head.num_inference_timesteps.

Run from the Isaac-GR00T checkout (uv env), e.g.:
  uv run python eval_heldout.py --model-path out/run1/checkpoint-6000 \
      --dataset-path /data/pickdrink_split/val --traj-ids 0 1 2 ... 19 \
      --modality-config-path /path/to/g1_brainco_config.py --json-out out/eval_6000.json

Written against the n1.7-release code; not executed by its author.
"""

import argparse
import importlib
import json
import sys
from pathlib import Path

import numpy as np
import torch

from gr00t.data.dataset.lerobot_episode_loader import LeRobotEpisodeLoader
from gr00t.data.dataset.sharded_single_step_dataset import extract_step_data
from gr00t.data.embodiment_tags import EmbodimentTag
from gr00t.policy.gr00t_policy import Gr00tPolicy


def load_modality_config(path: str | None) -> None:
    if path:
        p = Path(path)
        sys.path.append(str(p.parent))
        importlib.import_module(p.stem)


def build_obs(step, modality_cfg, repeats: int) -> dict:
    obs = {"video": {}, "state": {}, "language": {}}
    for k in modality_cfg["video"].modality_keys:
        arr = np.array(step.images[k])  # (T, H, W, C)
        obs["video"][k] = np.stack([arr] * repeats)
    for k in modality_cfg["state"].modality_keys:
        obs["state"][k] = np.stack([step.states[k]] * repeats)  # (B, T, D)
    for k in modality_cfg["language"].modality_keys:
        obs["language"][k] = [[step.text]] * repeats
    return obs


def evaluate_episode(policy, loader, row, tag, horizon, steps, repeats, rng_seed):
    modality_cfg = loader.modality_configs
    action_keys = modality_cfg["action"].modality_keys
    obs_cfg = {k: v for k, v in modality_cfg.items() if k != "action"}
    traj = loader[row]
    n = min(steps, len(traj)) if steps > 0 else len(traj)

    gt = np.concatenate([np.vstack(traj[f"action.{k}"].to_numpy()) for k in action_keys], axis=-1)[:n]
    preds, spreads = [], []
    for t0 in range(0, n, horizon):
        torch.manual_seed(rng_seed + t0)
        step = extract_step_data(traj, t0, obs_cfg, tag)
        action, _ = policy.get_action(build_obs(step, modality_cfg, repeats))
        chunk = np.concatenate([action[k] for k in action_keys], axis=-1)  # (K, H, D)
        preds.append(chunk[0, :horizon])
        if repeats > 1:
            spreads.append(chunk[:, :horizon].std(axis=0).mean(axis=0))  # (D,)
    pred = np.concatenate(preds, axis=0)[:n]

    dims = {}
    start = 0
    for k in action_keys:
        d = len(np.atleast_1d(traj[f"action.{k}"].iloc[0]))
        dims[k] = slice(start, start + d)
        start += d

    inside = np.ones(n - 1, dtype=bool)
    inside[np.arange(horizon - 1, n - 1, horizon)] = False  # transitions that cross chunks
    d_pred, d_gt = np.abs(np.diff(pred, axis=0)), np.abs(np.diff(gt, axis=0))
    out = {"length": n, "groups": {}}
    for k, s in dims.items():
        g = {
            "mae": float(np.abs(pred[:, s] - gt[:, s]).mean()),
            "mse": float(((pred[:, s] - gt[:, s]) ** 2).mean()),
            "mae_first_step": float(np.abs(pred[::horizon, s] - gt[::horizon, s]).mean()),
            "step_delta_pred_inside_chunk": float(d_pred[inside][:, s].mean()),
            "step_delta_gt": float(d_gt[:, s].mean()),
            "jump_pred_chunk_boundary": float(d_pred[~inside][:, s].mean()) if (~inside).any() else None,
        }
        if spreads:
            g["sample_std"] = float(np.stack(spreads)[:, s].mean())
        out["groups"][k] = g
    out["_pred"], out["_gt"], out["_dims"] = pred, gt, dims
    return out


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--model-path", required=True)
    ap.add_argument("--dataset-path", required=True)
    ap.add_argument("--embodiment-tag", default="new_embodiment")
    ap.add_argument("--modality-config-path", default=None)
    ap.add_argument("--traj-ids", type=int, nargs="+", required=True, help="ROW positions in episodes.jsonl")
    ap.add_argument("--action-horizon", type=int, default=16)
    ap.add_argument("--steps", type=int, default=0, help="0 = whole episode")
    ap.add_argument("--denoising-steps", type=int, default=None)
    ap.add_argument("--repeats", type=int, default=3, help="samples per observation for the spread metric")
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--json-out", default=None)
    args = ap.parse_args()

    load_modality_config(args.modality_config_path)
    tag = EmbodimentTag.resolve(args.embodiment_tag)
    policy = Gr00tPolicy(embodiment_tag=tag, model_path=args.model_path, device="cuda")
    if args.denoising_steps is not None:
        policy.model.action_head.num_inference_timesteps = args.denoising_steps
    loader = LeRobotEpisodeLoader(args.dataset_path, policy.get_modality_config(), video_backend="torchcodec")

    # range-normalised MAE uses the checkpoint's training statistics (q01/q99, absolute actions)
    stats = policy.processor.state_action_processor.statistics[tag.value]["action"]

    per_ep = {}
    all_abs_norm = {}
    for row in args.traj_ids:
        r = evaluate_episode(policy, loader, row, tag, args.action_horizon, args.steps,
                             args.repeats, args.seed)
        for k, s in r["_dims"].items():
            rng = np.maximum(np.array(stats[k]["q99"]) - np.array(stats[k]["q01"]), 1e-6)
            err = np.abs(r["_pred"][:, s] - r["_gt"][:, s]) / rng
            all_abs_norm.setdefault(k, []).append(err)
            r["groups"][k]["mae_range_norm"] = float(err.mean())
        for key in ("_pred", "_gt", "_dims"):
            r.pop(key)
        per_ep[row] = r
        print(f"row {row}: " + "  ".join(f"{k} mae={v['mae']:.4f}" for k, v in r["groups"].items()))

    summary = {}
    for k in next(iter(per_ep.values()))["groups"]:
        vals = [ep["groups"][k] for ep in per_ep.values()]
        summary[k] = {m: float(np.mean([v[m] for v in vals if v.get(m) is not None]))
                      for m in vals[0] if any(v.get(m) is not None for v in vals)}
    summary["ALL_range_norm_mae"] = float(np.mean(np.concatenate([np.concatenate(v) for v in all_abs_norm.values()], axis=None)))
    print(json.dumps(summary, indent=2))
    if args.json_out:
        Path(args.json_out).parent.mkdir(parents=True, exist_ok=True)
        json.dump({"model": args.model_path, "summary": summary, "per_episode": per_ep},
                  open(args.json_out, "w"), indent=2)


if __name__ == "__main__":
    main()
