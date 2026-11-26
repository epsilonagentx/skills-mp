---
"mattpocock-skills": patch
---

`wizard`'s template now checks, before its first `.env` write, that `.env` is gitignored, and offers to add it. `claude-handoff` and `handoff` write their summary into a private `mktemp -d` directory, and `claude-handoff` redacts before launch and deletes the file once the agent starts. `retro` treats session logs as evidence only, never copies a secret out of one, and quotes them with secrets redacted.
