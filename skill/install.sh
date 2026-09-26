#!/usr/bin/env bash
# Install the exam-to-qb skill from this repo into the AI tools' skill folders.
#
#   ~/.claude/skills/exam-to-qb   Claude Code
#   ~/.agents/skills/exam-to-qb   OpenAI Codex, Gemini CLI (shared interop path)
#
# Default is copy mode. Pass --link to symlink back at this repo instead, so
# `git pull` updates the skill in place with no re-install.
#
#   ./install.sh           # copy
#   ./install.sh --link    # symlink to the repo copy
#   ./install.sh --dry-run # show what would happen
set -euo pipefail

MODE=copy
DRY=0
for arg in "$@"; do
  case "$arg" in
    --link) MODE=link ;;
    --dry-run) DRY=1 ;;
    *) echo "未知參數：$arg" >&2; exit 2 ;;
  esac
done

REPO_SKILL="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/exam-to-qb"
[ -f "$REPO_SKILL/SKILL.md" ] || { echo "找不到 $REPO_SKILL/SKILL.md" >&2; exit 1; }

for spec in "Claude Code:$HOME/.claude/skills/exam-to-qb" \
            "Codex / Gemini CLI:$HOME/.agents/skills/exam-to-qb"; do
  name="${spec%%:*}"
  dest="${spec#*:}"
  echo "--- $name"
  echo "    $dest"

  if [ "$DRY" = 1 ]; then
    if [ "$MODE" = link ]; then echo "    [dry-run] 會建立符號連結指向 $REPO_SKILL"; else echo "    [dry-run] 會複製檔案"; fi
    continue
  fi

  mkdir -p "$(dirname "$dest")"
  # remove the link itself, never follow into its target
  [ -L "$dest" ] && rm -f "$dest"
  [ -e "$dest" ] && rm -rf "$dest"

  if [ "$MODE" = link ]; then
    ln -s "$REPO_SKILL" "$dest"
    echo "    OK - 已建立符號連結（git pull 後即自動更新）"
  else
    cp -R "$REPO_SKILL" "$dest"
    echo "    OK - 已複製"
  fi
done

echo
echo "驗證：python3 \"$REPO_SKILL/build.py\" --help"
if [ "$MODE" = copy ] && [ "$DRY" = 0 ]; then
  echo "提醒：這是複製模式，日後改了 repo 裡的技能要重跑本腳本；改用 ./install.sh --link 可免同步。"
fi
