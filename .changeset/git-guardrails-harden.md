---
"mattpocock-skills": patch
---

`git-guardrails-claude-code`'s hook no longer fails open without `jq`, and now catches the common respellings of the commands it blocks: git global options, quoted or full-path `git`, chained commands, `sh -c`, `eval`, `$(...)`, and inline or configured aliases. The skill now says plainly that the hook is a speed bump and recommends branch protection on the remote.
