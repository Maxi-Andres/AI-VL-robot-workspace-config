#!/usr/bin/env bash
# Installs the no-AI-attribution commit-msg hook into every repo of the workspace. Run it again
# after cloning a repo: .git/hooks is not versioned. Refuses to overwrite a different hook.
set -u
HOOK=~/Desktop/.claude/hooks/commit-msg-no-attribution
cd ~/Desktop
for g in $(find . -maxdepth 3 -name .git -type d | sort); do
  r=$(dirname "$g"); dest="$g/hooks/commit-msg"
  if [ -e "$dest" ] && ! cmp -s "$dest" "$HOOK"; then
    echo "SKIP $r: it has its own commit-msg hook (merge by hand)"; continue
  fi
  cp "$HOOK" "$dest" && chmod +x "$dest" && echo "ok   $r"
done
