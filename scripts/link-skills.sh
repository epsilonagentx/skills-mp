#!/usr/bin/env bash
set -euo pipefail

# NOTE: This is a dev-only script, intended for use by maintainers of this repo.
# It is not a supported installer. Modifications to it, or requests for
# modifications, will not be approved.
#
# Links all skills in the repository into the local skill directories used by
# each agent harness:
#   - ~/.claude/skills: Claude Code
#   - ~/.agents/skills: Codex and other Agent Skills-compatible harnesses
# Each entry is a symlink into this repo, so a `git pull` is all that's needed
# to keep installed skills up to date.

REPO="$(cd "$(dirname "$0")/.." && pwd)"
DESTS=("$HOME/.claude/skills" "$HOME/.agents/skills")
REPO_REAL="$(cd "$REPO" && pwd -P)"
skipped=0

# Collect the repo's skills once, link into every destination. `deprecated/`
# is retired, and `misc/` is kept around but rarely used and not promoted (see
# each bucket's own README): neither belongs in a daily-driver skill
# directory, so both are skipped here, same as everywhere else non-promoted
# skills are kept out. `in-progress/` IS still linked: it's public on purpose,
# feedback wanted, and this local install is exactly where that feedback loop
# runs.
names=()
srcs=()
while IFS= read -r -d '' skill_md; do
  src="$(dirname "$skill_md")"
  names+=("$(basename "$src")")
  srcs+=("$src")
done < <(find "$REPO/skills" -name SKILL.md -not -path '*/node_modules/*' -not -path '*/deprecated/*' -not -path '*/misc/*' -print0)

for DEST in "${DESTS[@]}"; do
  # If $DEST is a symlink that resolves into this repo, we'd end up writing the
  # per-skill symlinks back into the repo's own skills/ tree. Detect and bail
  # out instead of polluting the working copy.
  if [ -L "$DEST" ]; then
    resolved="$(readlink -f "$DEST")"
    case "$resolved" in
      "$REPO"|"$REPO"/*)
        echo "error: $DEST is a symlink into this repo ($resolved)." >&2
        echo "Remove it (rm \"$DEST\") and re-run; the script will recreate it as a real dir." >&2
        exit 1
        ;;
    esac
  fi

  mkdir -p "$DEST"

  for i in "${!names[@]}"; do
    name="${names[$i]}"
    src="${srcs[$i]}"
    target="$DEST/$name"

    # Never delete anything here: a real directory or file at $target may be a
    # skill installed by hand or from somewhere else. Only a symlink that points
    # into this repo, or at nothing, is replaced; everything else is skipped.
    if [ -L "$target" ]; then
      if [ -e "$target" ]; then
        case "$(readlink -f "$target")" in
          "$REPO_REAL"/*) ;;
          *)
            echo "skipped $name: $target links to $(readlink "$target"), outside this repo. Remove that link yourself to link this skill." >&2
            skipped=$((skipped + 1))
            continue
            ;;
        esac
      fi
    elif [ -e "$target" ]; then
      echo "skipped $name: $target already exists and is not a symlink. Move it aside yourself to link this skill." >&2
      skipped=$((skipped + 1))
      continue
    fi

    ln -sfn "$src" "$target"
    echo "linked $name -> $src ($DEST)"
  done
done

if [ "$skipped" -gt 0 ]; then
  echo "$skipped skill link(s) skipped; nothing was deleted. See the messages above." >&2
fi
