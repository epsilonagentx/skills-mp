---
name: git-guardrails-claude-code
description: Set up Claude Code hooks to block dangerous git commands (push, reset --hard, clean, branch -D, etc.) before they execute. Use when user wants to prevent destructive git operations, add git safety hooks, or block git push/reset in Claude Code.
---

# Setup Git Guardrails

Sets up a PreToolUse hook that intercepts and blocks dangerous git commands before Claude executes them.

## What Gets Blocked

- `git push` (all variants including `--force`)
- `git reset --hard`
- `git clean -f` / `git clean -fd` (any `-f` or `--force`)
- `git branch -D` (also `--delete --force`)
- `git checkout .` / `git restore .` (also `-- .`, `:/`, `*`; `git restore --staged .` is allowed)

The hook reads the command the way a shell would, so the common respellings are caught too: git's global options (`git -C dir push`, `git -c k=v push`, `--git-dir`), a quoted, escaped, or full-path `git`, wrappers such as `env`, `sudo`, and `xargs`, every command in a `;`, `&&`, or `|` chain, and commands inside `sh -c "..."`, `eval`, `$(...)`, and backticks. It also checks aliases defined inline (`git -c alias.p=push p`) or with `git config alias.*`.

When blocked, Claude sees a message telling it that it does not have authority to access these commands.

## What it is not

The hook is a **speed bump** against accidents, not a security boundary. It reads the command text, so anything built at run time gets past it: a variable (`$GIT push`), generated input to `eval`, a script on disk, or an alias that existed before the hook did. Tell the user this, and recommend, for anything that must never happen:

- **Branch protection on the remote** (no force pushes, no deletion, required reviews), which no local command can get around.
- Claude Code permission `deny` rules for the same commands, as a second layer.

It errs toward blocking. If it cannot read or check a command it blocks it, and text that only mentions `git push` (an `echo`, a commit message) is blocked too. It parses the hook input with `jq`, else `python3`, else a small reader of its own, so it no longer needs `jq` installed.

## Steps

### 1. Ask scope

Ask the user: install for **this project only** (`.claude/settings.json`) or **all projects** (`~/.claude/settings.json`)?

### 2. Copy the hook script

The bundled script is at: [scripts/block-dangerous-git.sh](scripts/block-dangerous-git.sh)

Copy it to the target location based on scope:

- **Project**: `.claude/hooks/block-dangerous-git.sh`
- **Global**: `~/.claude/hooks/block-dangerous-git.sh`

Make it executable with `chmod +x`.

### 3. Add hook to settings

Add to the appropriate settings file:

**Project** (`.claude/settings.json`):

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/block-dangerous-git.sh"
          }
        ]
      }
    ]
  }
}
```

**Global** (`~/.claude/settings.json`):

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/block-dangerous-git.sh"
          }
        ]
      }
    ]
  }
}
```

If the settings file already exists, merge the hook into the existing `hooks.PreToolUse` array. Don't overwrite other settings.

### 4. Ask about customization

Ask if user wants to add or remove any patterns from the blocked list. Edit the copied script accordingly.

### 5. Verify

Run a few quick tests:

```bash
echo '{"tool_input":{"command":"git push origin main"}}' | <path-to-script>; echo "exit $?"
echo '{"tool_input":{"command":"git -C . push --force"}}' | <path-to-script>; echo "exit $?"
echo '{"tool_input":{"command":"sh -c \"git reset --hard\""}}' | <path-to-script>; echo "exit $?"
echo '{"tool_input":{"command":"git status"}}' | <path-to-script>; echo "exit $?"
```

The first three should exit with code 2 and print a BLOCKED message to stderr. The last should exit 0 with no output.
