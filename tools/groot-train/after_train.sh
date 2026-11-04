#!/usr/bin/env bash
# Waits for both runs, then the held-out eval of every checkpoint, ONE AT A TIME (run next to
# training it took 9 of the 16 cores and halved the training speed). Logs: logs/after_train.log.
# 2026-11-04: with AV1 videos one checkpoint did not finish its first episode in 35 min —
# re-encode the val videos to H.264 first, or pass --steps.
set -uo pipefail
until grep -q ALL_DONE /workspace/logs/groot_two.log; do sleep 60; done
for c in pilot1500/checkpoint-1500 r10k/checkpoint-2500 r10k/checkpoint-5000 r10k/checkpoint-7500 r10k/checkpoint-10000; do
    [ -d "/workspace/runs/$c" ] || { echo "MISSING $c"; continue; }
    name=$(echo "$c" | sed "s#/checkpoint-#_#")
    [ -f "/workspace/evals/$name.json" ] && continue
    echo "$(date -u +%T) EVAL_START $name"
    /workspace/tools/eval_run.sh "/workspace/runs/$c" "$name" > "/workspace/logs/eval_$name.log" 2>&1 || echo "EVAL_FAILED $name"
    echo "$(date -u +%T) EVAL_END $name"
done
echo "$(date -u +%T) EVALS_ALL_DONE"
