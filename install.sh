#!/usr/bin/env bash
#
# Install / update RomkaLTU agent skills WITHOUT the Skills CLI.
# Idempotent: re-run any time to pull the latest and refresh the symlinks.
#
# Usage:
#   ./install.sh                 # installs the default skill(s): dev-flow
#   ./install.sh dev-flow other  # installs the named skills
#   curl -fsSL https://raw.githubusercontent.com/RomkaLTU/skills/main/install.sh | bash -s -- dev-flow
#
# Env overrides:
#   SKILLS_REPO        owner/repo            (default: RomkaLTU/skills)
#   SKILLS_REF         branch or tag         (default: main)
#   SKILLS_SRC         local clone dir       (default: ~/.local/share/agent-skills/<repo>)
#   SKILL_TARGET_DIRS  space-separated agent skill dirs to symlink into
#                      (default: ~/.claude/skills — only dirs that exist are used)

set -euo pipefail

REPO="${SKILLS_REPO:-RomkaLTU/skills}"
REF="${SKILLS_REF:-main}"
SRC_DIR="${SKILLS_SRC:-$HOME/.local/share/agent-skills/${REPO//\//-}}"

if [ "$#" -gt 0 ]; then SKILLS=("$@"); else SKILLS=("dev-flow"); fi

if [ -n "${SKILL_TARGET_DIRS:-}" ]; then
  read -r -a TARGETS <<< "$SKILL_TARGET_DIRS"
else
  # Only existing dirs are used, so listing candidates for other agents is harmless.
  TARGETS=("$HOME/.claude/skills" "$HOME/.cursor/skills" "$HOME/.config/opencode/skill")
fi

echo "▸ source: https://github.com/$REPO ($REF)"

# 1. clone or update the source repo
if [ -d "$SRC_DIR/.git" ]; then
  echo "▸ updating $SRC_DIR"
  git -C "$SRC_DIR" fetch --quiet origin "$REF"
  git -C "$SRC_DIR" checkout --quiet "$REF"
  git -C "$SRC_DIR" pull --ff-only --quiet origin "$REF"
else
  echo "▸ cloning into $SRC_DIR"
  mkdir -p "$(dirname "$SRC_DIR")"
  git clone --quiet --branch "$REF" "https://github.com/$REPO.git" "$SRC_DIR"
fi

# 2. symlink each requested skill into every target dir that exists
linked=0
for skill in "${SKILLS[@]}"; do
  skill_src="$SRC_DIR/skills/$skill"
  if [ ! -d "$skill_src" ]; then
    echo "  ✗ '$skill' not found in repo (skills/$skill missing)"; continue
  fi
  for tdir in "${TARGETS[@]}"; do
    [ -d "$tdir" ] || continue
    link="$tdir/$skill"
    if [ -L "$link" ] || [ ! -e "$link" ]; then
      rm -f "$link"
      ln -s "$skill_src" "$link"
      echo "  ✓ $skill → $link"
      linked=$((linked + 1))
    else
      echo "  ! $link exists and is not a symlink — skipping (remove it to relink)"
    fi
  done
done

if [ "$linked" -eq 0 ]; then
  echo "▸ no target skill dirs found. Create ~/.claude/skills or set SKILL_TARGET_DIRS."
else
  echo "▸ done. Update later by re-running this script (it pulls + relinks)."
fi
