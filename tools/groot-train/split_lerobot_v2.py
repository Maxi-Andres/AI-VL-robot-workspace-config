#!/usr/bin/env python3
"""Split a GR00T-flavoured LeRobot v2 dataset into train/ and val/ folders by episode.

Why this works with GR00T N1.7 (n1.7-release):
  * LeRobotEpisodeLoader iterates the ROWS of meta/episodes.jsonl and builds file
    paths from each row's own "episode_index" (chunk = episode_index // chunks_size),
    so a folder whose episodes.jsonl lists a subset of episodes, with their ORIGINAL
    indices and file names, loads correctly. No renumbering is needed.
  * generate_stats() globs data/*/*.parquet, so the train folder must contain ONLY the
    train parquet files (we link them one by one, never the whole directory).
  * stats.json / relative_stats.json are cached and silently reused if present, so they
    are NOT copied into train/: GR00T recomputes them from the train episodes only.
  * val/ gets a copy of stats.json only because the loader asserts the file exists;
    evaluation normalises with the statistics stored in the checkpoint, not these.
  * episodes_stats.jsonl and info.json totals are not read by GR00T; they are filtered
    and updated only to keep the folders self-consistent.

Files are symlinked (default) or hard-linked, so the split costs no disk space.

Usage:
  python split_lerobot_v2.py --src /data/pickdrink_v2 --out /data/pickdrink_split \
      --n-val 20 [--mode evenly|random] [--seed 0] [--link symlink|hardlink|copy]
  python split_lerobot_v2.py --src ... --out ... --val-episodes 3 17 42 ...
"""

import argparse
import json
import os
import random
import shutil
import sys
from pathlib import Path

CACHED_STATS = {"stats.json", "relative_stats.json"}
PER_EPISODE_META = {"episodes.jsonl", "episodes_stats.jsonl"}


def read_jsonl(path: Path) -> list[dict]:
    with open(path) as f:
        return [json.loads(line) for line in f if line.strip()]


def write_jsonl(path: Path, rows: list[dict]) -> None:
    with open(path, "w") as f:
        for row in rows:
            f.write(json.dumps(row) + "\n")


def place(src: Path, dst: Path, link: str) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    if dst.exists() or dst.is_symlink():
        dst.unlink()
    if link == "symlink":
        os.symlink(src.resolve(), dst)
    elif link == "hardlink":
        os.link(src, dst)
    else:
        shutil.copy2(src, dst)


def video_keys(info: dict) -> list[str]:
    return [k for k, v in info["features"].items() if v.get("dtype") == "video"]


def build_split(src: Path, dst: Path, episodes: list[dict], info: dict, link: str,
                is_train: bool, all_episode_stats: dict[int, dict]) -> None:
    if dst.exists():
        sys.exit(f"refusing to overwrite existing folder: {dst}")
    (dst / "meta").mkdir(parents=True)

    chunk_size = info["chunks_size"]
    n_files = 0
    for ep in episodes:
        idx = int(ep["episode_index"])
        chunk = idx // chunk_size
        rel = info["data_path"].format(episode_chunk=chunk, episode_index=idx)
        place(src / rel, dst / rel, link)
        n_files += 1
        for vk in video_keys(info):
            rel = info["video_path"].format(episode_chunk=chunk, video_key=vk, episode_index=idx)
            if (src / rel).exists():
                place(src / rel, dst / rel, link)
                n_files += 1
            else:
                print(f"  warning: missing video {rel}")

    # meta/: copy everything except per-episode files (filtered below) and, for train,
    # the cached statistics (must be recomputed from the train episodes only).
    for f in (src / "meta").iterdir():
        if f.name in PER_EPISODE_META or f.name == "info.json":
            continue
        if f.name in CACHED_STATS and (is_train or f.name == "relative_stats.json"):
            continue
        if f.is_file():
            shutil.copy2(f, dst / "meta" / f.name)

    write_jsonl(dst / "meta" / "episodes.jsonl", episodes)
    if all_episode_stats:
        keep = [all_episode_stats[int(e["episode_index"])] for e in episodes
                if int(e["episode_index"]) in all_episode_stats]
        write_jsonl(dst / "meta" / "episodes_stats.jsonl", keep)

    new_info = dict(info)
    new_info["total_episodes"] = len(episodes)
    new_info["total_frames"] = int(sum(int(e["length"]) for e in episodes))
    new_info["total_videos"] = len(episodes) * len(video_keys(info))
    new_info["splits"] = {"train" if is_train else "val": f"0:{len(episodes)}"}
    with open(dst / "meta" / "info.json", "w") as f:
        json.dump(new_info, f, indent=4)
    print(f"  {dst}: {len(episodes)} episodes, {new_info['total_frames']} frames, "
          f"{n_files} files linked ({link})")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--src", type=Path, required=True, help="converted LeRobot v2 dataset root")
    ap.add_argument("--out", type=Path, required=True, help="creates <out>/train and <out>/val")
    ap.add_argument("--n-val", type=int, default=20)
    ap.add_argument("--val-episodes", type=int, nargs="*", help="explicit episode_index values")
    ap.add_argument("--mode", choices=["evenly", "random"], default="evenly",
                    help="evenly = spread over the recording order (covers drift across sessions)")
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--link", choices=["symlink", "hardlink", "copy"], default="symlink")
    args = ap.parse_args()

    meta = args.src / "meta"
    info = json.load(open(meta / "info.json"))
    episodes = read_jsonl(meta / "episodes.jsonl")
    ep_stats_path = meta / "episodes_stats.jsonl"
    ep_stats = ({int(r["episode_index"]): r for r in read_jsonl(ep_stats_path)}
                if ep_stats_path.exists() else {})
    all_idx = [int(e["episode_index"]) for e in episodes]

    if args.val_episodes:
        val_idx = set(args.val_episodes)
        unknown = val_idx - set(all_idx)
        if unknown:
            sys.exit(f"unknown episode indices: {sorted(unknown)}")
    elif args.mode == "evenly":
        step = len(all_idx) / args.n_val
        # offset by half a step so neither the first nor the last episode is always picked
        val_idx = {all_idx[int(step / 2 + i * step)] for i in range(args.n_val)}
    else:
        val_idx = set(random.Random(args.seed).sample(all_idx, args.n_val))

    train_eps = [e for e in episodes if int(e["episode_index"]) not in val_idx]
    val_eps = [e for e in episodes if int(e["episode_index"]) in val_idx]

    print(f"source: {len(episodes)} episodes -> train {len(train_eps)}, val {len(val_eps)}")
    build_split(args.src, args.out / "train", train_eps, info, args.link, True, ep_stats)
    build_split(args.src, args.out / "val", val_eps, info, args.link, False, ep_stats)

    mapping = {row: int(e["episode_index"]) for row, e in enumerate(val_eps)}
    with open(args.out / "val_traj_ids.json", "w") as f:
        json.dump({"val_row_to_episode_index": mapping}, f, indent=2)
    print("open_loop_eval --traj-ids refer to ROW positions in val/meta/episodes.jsonl:")
    print("  --traj-ids " + " ".join(str(r) for r in mapping))
    print(f"  row -> original episode_index saved in {args.out / 'val_traj_ids.json'}")


if __name__ == "__main__":
    main()
