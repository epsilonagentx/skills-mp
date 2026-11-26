---
name: claude-handoff
description: Hand the current conversation off to a fresh background agent that picks up the work immediately.
argument-hint: "What will the next session be used for?"
disable-model-invocation: true
---

Write a handoff summary of the current conversation so a fresh agent can continue the work. Save it as `handoff.md` in a new directory made with `mktemp -d`, which gives it an unguessable name in the OS temporary directory that only the user can read. Then launch a background agent seeded with it as its prompt, and delete the file once the launch succeeds: `claude --bg --name "<descriptive name>" -- "$(cat <dir>/handoff.md)" && rm -f <dir>/handoff.md && rmdir <dir>`. Passing the file keeps the shell from running backticks or expanding `$` in the summary, and the prompt is already in the agent by the time the file goes. It starts in the current working directory and returns immediately; the user manages it with `claude agents`.

Always pass `-n`/`--name` with a descriptive name (e.g. `--name "Fix login bug"`); it sets the display name shown in the job list, session picker, and terminal title.

Include a "suggested skills" section in the summary, naming which skills the next agent should call the Skill tool for.

Do not duplicate content already captured in other artifacts (specs, plans, ADRs, issues, commits, diffs). Reference them by path or URL instead.

Before launching, re-read the summary and redact any sensitive information, such as API keys, tokens, passwords, `.env` values, credentials in URLs, or personally identifiable information. The summary becomes the agent's prompt, and while the agent runs its prompt is visible to other users of a shared machine in the process list.

If the user passed arguments, treat them as a description of what the next session will focus on and tailor the summary accordingly.
