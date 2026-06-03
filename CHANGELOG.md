# Changelog

## dev-flow

### 1.0.1
- Fix invalid YAML frontmatter in `SKILL.md`: the `description` was an unquoted
  plain scalar containing `": "` sequences, which broke `js-yaml` parsing and made
  the skill undetectable to the Skills CLI ("No valid skills found"). It's now a
  folded block scalar (`>-`).

### 1.0.0
- Initial release of the ticket-driven git workflow skill.
- Agent/LLM-agnostic: per-repo config and data live at `.dev-flow/` (`config.json`,
  `tickets/`, `time/`) — no vendor-specific (`.claude/`) paths.
- Self-initializing setup wizard runs when no `.dev-flow/config.json` exists.
- Flexible base-branch model: branches from and PRs back to the configured
  `git.baseBranch`; promotion between long-lived branches is out of scope.
- Plan-kickoff entry point (turn a plan / spec / PRD / todo into a branch + work).
- Vendor-neutral commit-skill detection (session skill list, with filesystem fallback).
