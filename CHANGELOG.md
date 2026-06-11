# Changelog

## dev-flow

### 1.3.0
- **Epic / subtask flow** (new Step 2.5 + `references/epic-subtasks.md`): when the
  ticket being started is a sub-issue of a parent ticket (an epic), the subtask now
  branches **from the epic's branch** and its PR targets the epic branch instead of
  `git.baseBranch`. The epic branch accumulates its subtasks and lands on base as one
  PR.
- Parent detection is automatic via the tracker when fetching the ticket at Step 2 —
  new **"Detect a parent"** sections in the Linear (`parent` field), Jira
  (`fields.parent`), and GitHub Issues (sub-issues via GraphQL) references. Manual /
  no-tracker setups and degraded mode enter the flow only when the user states the
  parent.
- If the epic has no branch yet, the first subtask bootstraps it from an up-to-date
  base as `<epics.branchPrefix>/<EPIC-ID>-<desc>` (default prefix `epic`).
- Statuses keep moving on the subtask ticket only; the epic ticket is never
  auto-transitioned. The **epic → base PR is always handed to the user** (the agent
  verifies the children and renders the command at close-out), consistent with the
  existing long-lived-branch scope note.
- New `epics` config block: `enabled` (default `true`) and `branchPrefix`
  (default `"epic"`).

### 1.2.0
- Skill selection (Step 5) is now **mode-aware** and safe for unattended runs.
  Instead of always pausing to ask which skills to load, the step resolves to one
  of three modes — `ask` (prompt the user, the interactive default), `auto`
  (select skills from the ticket context and load them without asking), or `skip`
  (load nothing).
- **Headless / non-interactive sessions force `auto`**, so an automated loop
  (e.g. a Ralph-style runner) loads the domain skills a slice needs based on the
  actual ticket — it no longer has to choose between blocking on `AskUserQuestion`
  and skipping skill loading entirely. Unattended downgrades `ask` to `auto`,
  never to `skip`.
- New `skillSelection.mode` config key (`"ask" | "auto" | "skip"`); the legacy
  `askBeforeImplementation` boolean still works (`true` → `ask`, `false` → `skip`).

### 1.1.0
- Commit, push, and PR creation now **hand off to the user by default** instead of
  running automatically. After implementation the agent prepares everything (commit
  message, push command, PR title/body, base-branch checks) and stops at each write
  step for the user to run manually — commit → push → PR.
- New `handoff` config block (`commit`, `push`, `pullRequest`), each defaulting to
  `true` (hand off). Set a key to `false` to let the agent perform that step itself;
  set all three false to restore the old fully-automatic flow.
- Generalizes the old commit-only `commitSkill.userInvokedOnly` flag, which is now
  the legacy equivalent of `handoff.commit: true` (and is the default regardless).
- Setup wizard now asks whether to use handoff (default) or automatic write steps.

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
