#!/usr/bin/env python3
"""Dry GR00T test, local half: N snapshots of the G1 (head frame + 26-D state), nothing sent.

State layout = the PickDrink dataset's: left arm q[15:22], right arm q[22:29] (rad), then the
BrainCo hands as pos/1000 (0 open .. 1 closed, finger order thumb flex, thumb aux, index,
middle, ring, pinky — the dataset starts episodes near 0 with the thumb aux ~0.7).
Frame: center-cropped to 4:3 and resized to 640x480 like the dataset's cam_left_high.

Run with the AI-VL-core venv (it has OpenCV):
  ~/Desktop/AI-VL-ecosystem/AI-VL-core/.venv/bin/python groot_snap.py --n 5 --every 2 --out snaps
"""
import argparse
import json
import os
import time
import urllib.request

import cv2

EXECUTOR = "http://127.0.0.1:8090"
RTSP = "rtsp://127.0.0.1:8554/g1"


def joint_line():
    req = urllib.request.Request(EXECUTOR + "/joints/stream?robot=g1")
    with urllib.request.urlopen(req, timeout=6) as r:
        for _ in range(150):       # the bridge starts on demand: the hands show up after ~1 s
            d = json.loads(r.readline())
            if (not d.get("stale") and d.get("q") and d.get("age_ms", -1) >= 0
                    and d.get("left") and d.get("right")):
                return d
    raise RuntimeError("no fresh joint state from the executor (is the G1 on and the relay up?)")


def state26(d):
    q = d["q"]
    hands = []
    for side in ("left", "right"):
        h = d.get(side)
        if not h:
            raise RuntimeError(f"{side} BrainCo hand not found in the joint stream")
        hands += [p / 1000.0 for p in h["pos"]]
    return q[15:22] + q[22:29] + hands


def frame(cap):
    for _ in range(10):          # drop what the decoder buffered: we want the frame of now
        cap.grab()
    ok, img = cap.read()
    if not ok:
        raise RuntimeError(f"no frame from {RTSP}")
    h, w = img.shape[:2]
    cw = min(w, h * 4 // 3)
    x0 = (w - cw) // 2
    return cv2.resize(img[:, x0:x0 + cw], (640, 480), interpolation=cv2.INTER_AREA)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=5)
    ap.add_argument("--every", type=float, default=2.0)
    ap.add_argument("--out", default="snaps")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    cap = cv2.VideoCapture(RTSP, cv2.CAP_FFMPEG)
    for i in range(a.n):
        img = frame(cap)
        d = joint_line()
        cv2.imwrite(os.path.join(a.out, f"{i}.jpg"), img, [cv2.IMWRITE_JPEG_QUALITY, 92])
        json.dump({"state": state26(d), "t": d["t"]}, open(os.path.join(a.out, f"{i}.json"), "w"))
        print(f"snap {i}: hands L {[round(x, 2) for x in state26(d)[14:20]]} "
              f"R {[round(x, 2) for x in state26(d)[20:26]]}")
        if i < a.n - 1:
            time.sleep(a.every)
    cap.release()


if __name__ == "__main__":
    main()
