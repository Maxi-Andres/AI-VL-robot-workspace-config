#!/usr/bin/env python3
"""Make an inference-only copy of a GR00T N1.7 checkpoint with weights cast to bfloat16.

Gr00tPolicy (n1.7-release, gr00t/policy/gr00t_policy.py) loads the model and immediately
does model.to(device, dtype=torch.bfloat16), so storing fp32 weights buys nothing at
inference. This halves the ~12.6 GB of safetensors. The copy CANNOT be used to resume
training (no optimizer, bf16 master weights). Untested by its author.

  python shrink_checkpoint_bf16.py out/run1/checkpoint-10000 /volume/ckpt10000_bf16
"""

import json
import shutil
import sys
from pathlib import Path

import torch
from safetensors.torch import load_file, save_file

SKIP = {"optimizer.pt", "scheduler.pt", "rng_state.pth", "scaler.pt"}


def main(src: Path, dst: Path) -> None:
    dst.mkdir(parents=True, exist_ok=False)
    total = 0
    for f in sorted(src.iterdir()):
        if f.name in SKIP or f.name.startswith("global_step"):
            continue
        if f.suffix == ".safetensors":
            tensors = load_file(str(f))
            tensors = {k: (v.to(torch.bfloat16) if v.is_floating_point() else v) for k, v in tensors.items()}
            total += sum(v.numel() * v.element_size() for v in tensors.values())
            save_file(tensors, str(dst / f.name), metadata={"format": "pt"})
        elif f.is_dir():
            shutil.copytree(f, dst / f.name)
        else:
            shutil.copy2(f, dst / f.name)
    index = dst / "model.safetensors.index.json"
    if index.exists():
        data = json.load(open(index))
        data.setdefault("metadata", {})["total_size"] = total
        json.dump(data, open(index, "w"), indent=2)
    print(f"wrote {dst} ({total / 1e9:.2f} GB of weights)")


if __name__ == "__main__":
    main(Path(sys.argv[1]), Path(sys.argv[2]))
