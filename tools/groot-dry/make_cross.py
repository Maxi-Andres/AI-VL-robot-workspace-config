"""Cross test snapshots: which input drives the policy, the image or the state?

  0 ours      : our frame + our state (the dry run's snap 0)
  1 black     : black frame + our state
  2 val_start : held-out episode frame 0 + its own state
  3 val_mid   : held-out episode frame at 40% (arm on the way) + its own state
  4 val_img   : held-out frame 0 + OUR state
  5 our_img   : our frame + the held-out episode's state at frame 0
"""
import glob
import json
import os
import shutil

import cv2
import numpy as np
import pandas as pd

V = "/workspace/datasets/pickdrink_split/val"
OUT = "/workspace/dry/cross"
os.makedirs(OUT, exist_ok=True)

ours_s = json.load(open("/workspace/dry/snaps/0.json"))["state"]
ours_img = cv2.imread("/workspace/dry/snaps/0.jpg")

pq = sorted(glob.glob(f"{V}/data/*/*.parquet"))[0]
ep = os.path.basename(pq)[:-8]
states = np.stack(pd.read_parquet(pq)["observation.state"].values)
mp4 = glob.glob(f"{V}/videos/*/observation.images.cam_left_high/{ep}.mp4")[0]


def frame_at(idx):
    # The dataset's videos are AV1, which OpenCV's ffmpeg cannot decode: torchcodec, like the eval.
    from torchcodec.decoders import VideoDecoder
    rgb = VideoDecoder(mp4)[idx].permute(1, 2, 0).numpy()
    return cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR)


mid = int(len(states) * 0.4)
v0, vm = frame_at(0), frame_at(mid)
cases = [(ours_img, ours_s), (np.zeros_like(ours_img), ours_s), (v0, states[0].tolist()),
         (vm, states[mid].tolist()), (v0, ours_s), (ours_img, states[0].tolist())]
for i, (img, s) in enumerate(cases):
    cv2.imwrite(f"{OUT}/{i}.jpg", img)
    json.dump({"state": [float(x) for x in s]}, open(f"{OUT}/{i}.json", "w"))
print("CROSS_READY", ep, "frames", len(states), "mid", mid)
