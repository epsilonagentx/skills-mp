# The canonical install block

One install story, one wording. `README.md` and `.changeset/*` must say **this** and nothing else. Change it here first, then propagate. `docs/` pages carry no install commands (see [writing-docs.md](./writing-docs.md)).

## Claude Code only, pinned to a tested tag

The team installs `epsilonagentx-skills` from this fork's marketplace, `epsilonagentx` (`.claude-plugin/marketplace.json` and `plugin.json`). The `add` command pins the marketplace to a signed `team-vX.Y.Z` tag on the commit that was tested, so a teammate gets exactly that commit and nothing newer. Auto-update is off for third-party marketplaces, and with `version` set an install only moves when that string changes, so a new release means a new tag and a re-add.

The `claude-plugins-official` listing installs upstream's `mattpocock-skills` from `mattpocock/skills`: every promoted skill, without this fork's fixes. Never point the team at it.

Other agents (Codex, Copilot, Gemini CLI, skills.sh) are not supported. Their upstream routes install every promoted skill instead of the vetted subset, and nobody has run them against this fork. The README says so in one line and points at upstream.

## Cutting a new tag

1. In one commit, add the vetted skills to `plugin.json`, bump `version` in `package.json` and `plugin.json` together, and change the tag in the block below and in `README.md` to `team-vX.Y.Z`, where `X.Y.Z` is the new `version`.
2. Create a signed tag on that commit (`git tag -s team-vX.Y.Z <sha>`) and push only the tag.
3. In a throwaway project, add and install from the tag with `--scope project`. Check that the marketplace clone is at the tagged commit and that only the listed skills load.

Once teammates have installed from a tag, don't move it. Cut a new one.

## Claude Code

<canonical-block name="claude-code">

```bash
claude plugin marketplace add 'epsilonagentx/skills-mp#team-v1.3.2'
claude plugin install epsilonagentx-skills@epsilonagentx
```

Pinned to the tested release `team-v1.3.2`, so it doesn't update itself. To move to a newer tag, remove the marketplace, then add and install again:

```bash
claude plugin marketplace remove epsilonagentx
claude plugin marketplace add 'epsilonagentx/skills-mp#team-vX.Y.Z'
claude plugin install epsilonagentx-skills@epsilonagentx
```

No SSH key for GitHub? Run `export CLAUDE_CODE_PLUGIN_PREFER_HTTPS=1` first. The repo is public, so HTTPS needs no login.

</canonical-block>

## Other agents

<canonical-block name="other-agents">

This fork supports Claude Code only. For other agents, use upstream [mattpocock/skills](https://github.com/mattpocock/skills), which this fork hasn't vetted.

</canonical-block>
