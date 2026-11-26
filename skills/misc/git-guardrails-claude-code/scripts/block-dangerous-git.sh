#!/usr/bin/env bash
# Claude Code PreToolUse hook: blocks destructive git commands.
#
# This is a speed bump against accidents, not a security boundary. It reads the
# command text, so a command built at run time (a variable, generated input to
# eval, a script on disk, an alias set up before this hook) gets past it. Pair
# it with branch protection on the remote for anything that must never happen.
#
# It errs toward blocking: if it cannot read or check the command, it blocks,
# and text that merely mentions "git push" (an echo, a commit message) is
# blocked too.
#
# Exit 2 blocks the tool call and shows stderr to Claude. Exit 0 allows it.

INPUT="$(cat)"

# Read .tool_input.command with jq, else python3, else hand the raw JSON to the
# awk reader below. Never let a missing parser wave a command through.
RAW=""
if CMD="$(jq -er '.tool_input.command' <<<"$INPUT" 2>/dev/null)"; then
  :
elif CMD="$(python3 -I -c 'import json, sys; print(json.load(sys.stdin)["tool_input"]["command"])' <<<"$INPUT" 2>/dev/null)"; then
  :
else
  CMD="$INPUT"
  RAW=1
fi

# The checker splits the command the way a shell would (quotes, escapes,
# separators, redirections, $(...) and backticks), finds every git invocation,
# skips git's global options to reach the subcommand, and looks inside quoted
# strings and substitutions, which `sh -c` or eval may run.
# shellcheck disable=SC2016
CHECKER='
function jsoncmd(s,    i, n, c, e, out) {
  i = index(s, "\"command\"")
  if (!i) return s
  s = substr(s, i + 9)
  if (!sub(/^[ \t\r\n]*:[ \t\r\n]*"/, "", s)) return s
  n = length(s)
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (c == "\"") return out
    if (c == "\\") {
      i++; e = substr(s, i, 1)
      if (e == "n") out = out "\n"
      else if (e == "t") out = out "\t"
      else if (e == "u") { out = out "?"; i += 4 }
      else out = out e
      continue
    }
    out = out c
  }
  return out
}

function endword(st, words) {
  if (st["inw"]) {
    if (st["skip"]) st["skip"] = 0
    else words[++st["nw"]] = st["w"]
  }
  st["w"] = ""; st["inw"] = 0
}

function scan(s, depth,    st, words, subs, nsub, n, i, j, k, c, nx, ch, dep, r) {
  if (depth > 4) return ""
  st["w"] = ""; st["inw"] = 0; st["skip"] = 0; st["nw"] = 0; nsub = 0
  n = length(s)
  for (i = 1; i <= n + 1; i++) {
    c = (i > n) ? "\n" : substr(s, i, 1)
    nx = substr(s, i + 1, 1)
    if (c == "\047") {
      j = index(substr(s, i + 1), "\047")
      if (j == 0) { st["w"] = st["w"] substr(s, i + 1); i = n }
      else { st["w"] = st["w"] substr(s, i + 1, j - 1); i += j }
      st["inw"] = 1; continue
    }
    if (c == "\"") {
      st["inw"] = 1
      for (i++; i <= n; i++) {
        ch = substr(s, i, 1)
        if (ch == "\\" && i < n) { i++; st["w"] = st["w"] substr(s, i, 1); continue }
        if (ch == "\"") break
        st["w"] = st["w"] ch
      }
      if (i > n) i = n
      continue
    }
    if (c == "\\") {
      if (i >= n) continue
      if (nx != "\n") { st["w"] = st["w"] nx; st["inw"] = 1 }
      i++; continue
    }
    if (c == "`") {
      j = index(substr(s, i + 1), "`")
      if (j == 0) { subs[++nsub] = substr(s, i + 1); i = n }
      else { subs[++nsub] = substr(s, i + 1, j - 1); i += j }
      st["w"] = st["w"] "$SUB"; st["inw"] = 1; continue
    }
    if (c == "$" && nx == "(") {
      dep = 0
      for (j = i + 1; j <= n; j++) {
        ch = substr(s, j, 1)
        if (ch == "(") dep++
        else if (ch == ")" && --dep == 0) break
      }
      subs[++nsub] = substr(s, i + 2, j - i - 2)
      i = (j > n) ? n : j
      st["w"] = st["w"] "$SUB"; st["inw"] = 1; continue
    }
    if (c == "#" && !st["inw"]) {
      j = index(substr(s, i + 1), "\n")
      i = (j == 0) ? n : i + j - 1
      continue
    }
    if (c == " " || c == "\t") { endword(st, words); continue }
    if (c == "<" || c == ">" || (c == "&" && nx == ">")) {
      if (st["inw"] && st["w"] ~ /^[0-9]+$/) { st["w"] = ""; st["inw"] = 0 }
      else endword(st, words)
      while (i < n && index("<>&|-", substr(s, i + 1, 1))) i++
      st["skip"] = 1
      continue
    }
    if (c == "\n" || c == ";" || c == "&" || c == "|" || c == "(" || c == ")") {
      endword(st, words); st["skip"] = 0
      r = check(words, st["nw"], depth)
      if (r != "") return r
      st["nw"] = 0; continue
    }
    st["w"] = st["w"] c; st["inw"] = 1
  }
  for (k = 1; k <= nsub; k++) {
    r = scan(subs[k], depth + 1)
    if (r != "") return r
  }
  return ""
}

function check(words, nw, depth,    k, m, wd, base, r) {
  for (k = 1; k <= nw; k++) {
    wd = words[k]
    if (wd ~ /[ \t\n;&|]/) { r = scan(wd, depth + 1); if (r != "") return r }
    base = wd; sub(/.*\//, "", base); base = tolower(base)
    if (base == "git" || base == "git.exe") r = checkgit(words, k + 1, nw, depth, "")
    else if (base ~ /^git-[a-z]+$/) r = checkgit(words, k + 1, nw, depth, substr(base, 5))
    else r = ""
    if (r != "") return r
    # Alias-proof catch-alls, kept from the original pattern list.
    if (wd == "push") for (m = k + 1; m <= nw; m++) if (words[m] ~ /^--force/ || words[m] == "-f") return "push --force"
    if (wd == "reset") for (m = k + 1; m <= nw; m++) if (words[m] == "--hard") return "reset --hard"
  }
  return ""
}

function aliasvalue(v, depth) {
  if (substr(v, 1, 1) == "!") return scan(substr(v, 2), depth + 1)
  return scan("git " v, depth + 1)
}

function checkgit(words, j, nw, depth, cmd,    m, a, r, hard, D, del, frc, staged, wt, whole) {
  if (cmd == "") {
    while (j <= nw && words[j] ~ /^-/) {
      a = words[j]
      if (a == "-c" && j < nw && words[j + 1] ~ /^alias\..*=/) {
        r = aliasvalue(substr(words[j + 1], index(words[j + 1], "=") + 1), depth)
        if (r != "") return "an inline alias for " r
      }
      if (a ~ /^(-C|-c|--git-dir|--work-tree|--namespace|--config-env|--super-prefix)$/) j += 2
      else j++
    }
    if (j > nw) return ""
    cmd = words[j++]
  }
  if (cmd == "push") return "git push"
  if (cmd == "config") {
    for (m = j; m < nw; m++)
      if (words[m] ~ /^alias\./) {
        r = aliasvalue(words[m + 1], depth)
        if (r != "") return "an alias for " r
      }
    return ""
  }
  hard = D = del = frc = staged = wt = whole = 0
  for (m = j; m <= nw; m++) {
    a = words[m]
    if (a ~ /^-[^-]/) {
      if (a ~ /D/) D = 1
      if (a ~ /d/) del = 1
      if (a ~ /f/) frc = 1
      if (a ~ /S/) staged = 1
      if (a ~ /W/) wt = 1
    }
    else if (a == "--hard") hard = 1
    else if (a == "--delete") del = 1
    else if (a == "--force") frc = 1
    else if (a == "--staged") staged = 1
    else if (a == "--worktree") wt = 1
    else if (a ~ /^(\.|\.\/|\.\/\*|:\/|:\/\.|:\/\*|:\(top\)|\*)$/) whole = 1
  }
  if (cmd == "reset" && hard) return "git reset --hard"
  if (cmd == "clean" && frc) return "git clean --force"
  if (cmd == "branch" && (D || (del && frc))) return "git branch -D"
  if (cmd == "checkout" && whole) return "git checkout over the whole tree"
  if (cmd == "restore" && whole && !(staged && !wt)) return "git restore over the whole tree"
  return ""
}

BEGIN {
  s = ""
  while ((getline line) > 0) s = s line "\n"
  if (raw) s = jsoncmd(s)
  r = scan(s, 0)
  if (r != "") print r
}
'

if ! REASON="$(printf '%s' "$CMD" | awk -v raw="$RAW" "$CHECKER")"; then
  echo "BLOCKED: the git guardrail hook could not check this command, so it did not run. Check that awk works in this shell." >&2
  exit 2
fi

if [ -n "$REASON" ]; then
  printf "BLOCKED: '%s' runs %s. The user has prevented you from doing this.\n" "$CMD" "$REASON" >&2
  exit 2
fi

exit 0
