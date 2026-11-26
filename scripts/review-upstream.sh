#!/usr/bin/env bash
set -euo pipefail

# Review what upstream changed before you pull it into this fork.
#
# Skills are prompts that agents follow with your permissions, and the scripts
# beside them run on your machine, so an upstream change deserves a read before
# it lands. This script fetches upstream into a local ref, then prints:
#   - every new commit, with its signature status
#   - the files changed
#   - flags worth a closer look: hidden Unicode, HTML comments in Markdown,
#     new links to outside hosts, new or changed executables, changes to CI,
#     manifests and scripts, and a few risky shell patterns
# It never merges, rebases, or touches your working tree. A flag is a prompt
# to read that part of the diff, not a verdict.
#
# Usage: scripts/review-upstream.sh [local-ref]
#   local-ref         the branch you would merge into (default: main)
# Environment:
#   UPSTREAM_URL      default: https://github.com/mattpocock/skills.git
#   UPSTREAM_BRANCH   default: main

UPSTREAM_URL="${UPSTREAM_URL:-https://github.com/mattpocock/skills.git}"
UPSTREAM_BRANCH="${UPSTREAM_BRANCH:-main}"
LOCAL_REF="${1:-main}"
REVIEW_REF="refs/upstream-review/$UPSTREAM_BRANCH"

cd "$(dirname "$0")/.."

section() { printf '\n== %s ==\n' "$1"; }

git fetch --quiet --no-tags "$UPSTREAM_URL" "+refs/heads/$UPSTREAM_BRANCH:$REVIEW_REF"
UP="$(git rev-parse "$REVIEW_REF")"
LOCAL="$(git rev-parse --verify "$LOCAL_REF^{commit}")"

if ! BASE="$(git merge-base "$LOCAL" "$UP")"; then
  echo "$LOCAL_REF and upstream share no history. Refusing to compare them." >&2
  exit 1
fi

if [ "$BASE" = "$UP" ]; then
  echo "Nothing new upstream: $LOCAL_REF already contains $UPSTREAM_URL $UPSTREAM_BRANCH (${UP:0:12})."
  exit 0
fi

section "Upstream $UPSTREAM_URL $UPSTREAM_BRANCH at ${UP:0:12}, compared from ${BASE:0:12}"

section "Commits (G good signature, U good but untrusted key, E key not in your keyring, N unsigned, B BAD)"
git log --format='%h %G? %ad %an: %s' --date=short "$BASE..$UP"

section "Files changed"
git diff --stat=120 "$BASE" "$UP"

section "Flags"
flags="$(
  {
    # New executables, and files whose mode changed to executable.
    git diff --summary "$BASE" "$UP" | grep -E '100755' | sed 's/^ */executable: /' || true

    # Paths that run code or change what gets installed.
    git diff --name-only "$BASE" "$UP" | while IFS= read -r path; do
      case "$path" in
        .github/* | .claude-plugin/* | scripts/* | package.json | package-lock.json | .npmrc | \
          *.sh | *.mjs | *.js | *.ts | *.py | */hooks/* | *.yaml | *.yml)
          echo "runs or ships code: $path"
          ;;
      esac
    done

    # Patterns in the added lines.
    git diff --no-color --no-ext-diff -U0 "$BASE" "$UP" | perl -CSD -ne '
      BEGIN { %seen_host = () }
      if (/^\+\+\+ (?:b\/)?(.*)$/) { $file = $1; next }
      if (/^@@ [^+]*\+(\d+)/) { $n = $1; next }
      next unless /^\+/;
      my $line = substr($_, 1); chomp $line;
      my $at = "$file:$n"; $n++;
      if ($line =~ /[\x{200B}-\x{200F}\x{202A}-\x{202E}\x{2060}-\x{2064}\x{2066}-\x{2069}\x{FEFF}\x{E0000}-\x{E007F}]/) {
        (my $shown = $line) =~ s/([\x{200B}-\x{200F}\x{202A}-\x{202E}\x{2060}-\x{2064}\x{2066}-\x{2069}\x{FEFF}\x{E0000}-\x{E007F}])/sprintf("<U+%04X>", ord $1)/ge;
        print "hidden or bidi Unicode at $at: $shown\n";
      }
      print "HTML comment in Markdown (invisible when rendered, read by agents) at $at\n"
        if $file =~ /\.md$/ && $line =~ /<!--/;
      print "pipes a download into a shell at $at\n"
        if $line =~ /\b(?:curl|wget)\b.*\|\s*(?:ba|z)?sh\b/;
      print "decodes base64 at $at\n" if $line =~ /base64\s+(?:-d|--decode)\b/;
      print "uses eval at $at\n" if $line =~ /\beval\b/;
      print "deletes recursively at $at\n" if $line =~ /\brm\s+-[a-zA-Z]*r[a-zA-Z]*f|\brm\s+-[a-zA-Z]*f[a-zA-Z]*r/;
      print "reads like a prompt injection at $at\n"
        if $line =~ /\b(?:ignore|disregard|forget)\b.{0,20}\b(?:previous|prior|above|earlier)\b.{0,20}\binstructions?\b/i;
      while ($line =~ m{https?://([A-Za-z0-9.-]+)}g) {
        my $host = lc $1;
        next if $host =~ /(?:^|\.)(?:aihero\.dev|github\.com)$/;
        print "first new link to $host at $at\n" unless $seen_host{$host}++;
      }
    '
  } | sort -u
)"

if [ -n "$flags" ]; then
  printf '%s\n' "$flags" | sed 's/^/  ! /'
  echo "  $(printf '%s\n' "$flags" | wc -l | tr -d ' ') flag(s). Read those parts of the diff before merging."
else
  echo "  none"
fi

section "Next"
echo "Nothing was merged. Read the full diff with:"
echo "  git diff $BASE $UP"
echo "To take it, merge the exact commit you reviewed, not the branch, which may have moved since:"
echo "  git switch $LOCAL_REF && git merge $UP"
