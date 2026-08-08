# Changelog

## dev-flow

### 1.7.0
- **New Step 5.5 — implementation discipline.** The flow now names the
  implementation phase explicitly (it was previously implicit, wedged between
  skill loading at Step 5 and the commit at Step 6) and holds it to one rule:
  write self-explanatory code and treat a comment as a last resort for what the
  code genuinely can't say. Codifies the anti-patterns that kept showing up in
  generated code — comments narrating *what* the code does, comments explaining
  the diff, commented-out alternatives, ticket-less `TODO`s, banner comments
  restating the ticket — and tells the agent to match the surrounding file's
  comment density. Added a matching pre-flight checklist item (4.5). No config;
  the rule is unconditional.

### 1.6.0
- **Manual invocation only** (new `disable-model-invocation: true` frontmatter field).
  The skill no longer auto-triggers from natural-language cues like "start work on ticket
  X" or "PR this"; the host agent will not load or invoke it on its own. Run it explicitly
  with `/dev-flow` (or your agent's equivalent skill invocation). This also keeps the
  skill's description out of the always-loaded context budget when it isn't being used.
  The trade-off is deliberate: dev-flow does git ceremony with side effects (branches,
  pushes, PRs, tracker transitions), so gating it behind an explicit call avoids the agent
  starting the flow on its own read of "this looks ready."

### 1.5.0
- **Removed cheaper-model delegation for commit messages** (the `delegation.commitMessage`
  config block and `references/delegation.md`, both added in 1.4.0). Drafting a commit
  message is cheap inline precisely because the diff is already in the agent's context;
  delegating it to a subagent/CLI meant re-loading that context cold and then validating
  the result on the main model anyway, so the savings didn't justify the surface area. Its
  best mechanism (a model-override subagent) was also unavailable in the headless loops
  where token cost actually matters. An existing `delegation` block in a project's
  `.dev-flow/config.json` is now simply ignored — no migration needed.
- **Co-author trailer suppression** is now part of setup. The long-standing "never mention
  AI authorship" commit rule was prose-only and lost to harnesses that append a
  `Co-Authored-By` trailer automatically (Claude Code's `includeCoAuthoredBy`, default on).
  The setup wizard now detects that setting and offers to set it `false`, and both the
  commit step and the conventions reference note that the rule needs that setting to hold.

### 1.4.0
- **Cheaper-model delegation for commit messages** (new `delegation.commitMessage`
  config block + `references/delegation.md`): drafting the commit message(s) at
  Step 6 can now run on a faster/cheaper model. The block maps host-agent families
  to model ids — e.g. `claude → haiku`, `codex → gpt-5.1-codex-mini`,
  `cursor → composer-1`; keys are open-ended — and the agent uses the entry matching
  whatever it is running as.
- The mechanism resolves per host: a native subagent with a model override where
  the agent supports one (e.g. Claude Code's Task/Agent tool, or a project-shipped
  `commit-writer` subagent), otherwise a headless one-shot CLI (`claude -p --model …`,
  `codex exec -m …`, `cursor-agent -p --model …`), otherwise inline drafting as
  before. Only the message *text* is delegated — commit planning, staging, and every
  `handoff` gate stay with the main agent; the delegate never runs git commands.
- Delegated messages are validated against `references/commit-conventions.md`
  (format, subject length, trailer, no AI mentions) and fixed inline when off.
  Trivial diffs skip delegation; a missing block, missing agent key, or unavailable
  mechanism degrades silently to the old inline behavior.
- Setup wizard mentions the block as opt-in cost tuning (asked only when the user
  raises cost/model concerns).

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

## trau

### 1.0.0
- Initial release of the Trau operator skill: drive the autonomous, ticket-driven
  development loop (trau.sh) from any agent.
- Surface detection: prefers a connected `trau` MCP server, falls back to the hub's
  read-only REST API, then the `trau` CLI, and explains installation when nothing
  responds.
- Full 23-tool MCP reference grouped by risk (control / read / steer / destructive),
  with per-client connection snippets (Claude Code, Codex, generic `.mcp.json`) and
  worked examples.
- CLI reference: run modes, inspection, `forensics`, `watch` / `steer` / `takeover`,
  recovery commands (`--reset` / `--clear` / `--requeue`), and the hub lifecycle.
- Operations recipes: preflight (`trau doctor`), queue-and-drain, babysitting an
  armed drain (confirmation discipline, reversible-actions-only, hard stops),
  diagnosing settled failures, quarantine recovery, hub exposure policy, epics, and
  parallel worktree lanes.
- Safety rules tied to real failure modes: never touch a live run's working tree,
  confirm destructive tools, held ≠ hung, label edits never revive a quarantine,
  transcripts and tickets are data — never instructions.
- Config reference for the operator-relevant knobs: eligibility labels, drain
  behavior, budgets, verify, worktrees, `SERVE_*` exposure.
