# Changelog

## commit

### 1.0.1
- **Point at the current attribution setting.** The no-AI-attribution rule told
  readers to set `includeCoAuthoredBy: false`, which is deprecated in Claude
  Code's settings schema and never governed the `Claude-Session:` link — so a
  reader who followed it still got a session trailer in every commit. The rule
  now gives `"attribution": { "commit": "", "sessionUrl": false }`, says which
  key does what, and notes the old key still works.

### 1.0.0
- **First release.** Extracts Trau's commit convention into a standalone,
  explicitly-invoked skill (`/commit`, optionally `/commit COD-123`): read the
  repo's own convention first (commitlint config, `CONTRIBUTING.md`/`AGENTS.md`,
  the last twenty subjects), group the working tree into atomic
  dependency-ordered commits, write a Conventional Commits subject that is
  imperative, lower-case and under 72 characters, stage by name, and commit.
  Stops at the commit — no push, no PR, no tracker transition.
- **The ticket is optional.** It is resolved from the invocation argument, then
  the branch name, then `.dev-flow/config.json`. When none is found the commit
  says nothing about tickets at all: no `Refs:` trailer, and no `(no-issue)`,
  `NO-JIRA`, `Refs: none` or body sentence standing in for one.
- **No AI attribution, enforced in two places** — the message rules forbid
  `Co-authored-by:`, `Claude-Session:` and generation banners, and the skill
  points at `includeCoAuthoredBy: false` because prose cannot suppress a trailer
  the harness appends.
- `disable-model-invocation: true`, matching dev-flow: committing has side
  effects, and dev-flow's handoff already asks the user to run the commit skill
  by hand.

## dev-flow

### 1.8.1
- **Point at the current attribution setting.** Step 6, the commit-conventions
  reference and the setup wizard all told readers to set
  `includeCoAuthoredBy: false` — deprecated, and blind to the `Claude-Session:`
  link, so commits kept carrying a trailer the convention forbids. All three now
  give `"attribution": { "commit": "", "sessionUrl": false }`. The wizard greps
  for either key, treats an existing `includeCoAuthoredBy: false` as already
  handled, and warns that `sessionUrl: false` also drops the session link from
  PR bodies.

### 1.8.0
- **Time estimates are confirmed once, at close-out — not when the PR opens.**
  Step 8 previously stopped to ask the user to confirm the round's number before
  the work was accepted, which is premature: review comments and QA findings both
  add entries, so the total is still moving. Step 8 now appends the entry as
  *provisional* and says nothing; Step 9 presents the accumulated total and asks
  for the one confirmation. Where a QA stage sits between merge and Done (the
  ticket parks in "Ready for QA" instead of closing on merge), both the Done
  transition and the time question wait for QA sign-off. Entries carry a new
  `confirmed` field, `false` until close-out flips them. Pre-flight items 8 and 9
  updated to match.

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

### 1.4.0
- **Re-documented against trau v2.72.0** (main at 2026-10-02). The hub MCP grew
  from 75 to 85 tools, and `mcp.md` now lists every one:
  - Terminal sessions: `list_terminal_sessions`, `read_terminal_screen`;
  - Data sources: `list_data_sources`, `describe_data_source`;
  - checklist evidence checks: `check_checklist_item`, `check_checklist`,
    `promote_checklist_item`, and the item's `check` command;
  - Publish website task and Worker deploys: `publish_website_status`,
    `retry_publish_website`, `worker_deploy_status`.
- **New `references/hub-features.md`** for the hub features an operator meets but
  does not drive: Terminal sessions, the App page and its checkout hold, the
  Assistant, Data sources, and Report-derived ADRs.
- **New hold gate `app-session`** (`Waiting on the App`), a deliberate wait: never
  requeue, reset or quarantine for it.
- **New safety rules:** never stop a sibling lane to make room for a recovery tool;
  never type into a Terminal session or drive the Assistant; set
  `SERVE_ALLOW_TERMINAL` or `DATA_ASK_SAMPLES` only on the user's word.
- Smaller updates: the `testinstructions` artifact kind, the split check of
  `AI_ASSESSMENT`, Stacked epic eligibility, the Publish website task, and the
  native Windows installer.
- `cli.md`, `config.md`, `mcp.md` and `operations.md` now start with a table of
  contents.

### 1.3.0
- **Re-documented against trau v2.67.0** (main at 2026-09-26; 1.2.0 described
  2.53.0). Every tool, command, key, status, gate and class was re-traced to the
  source and the ADRs landed since (0075–0142).
- **The hub MCP more than doubled: 33 → 75 tools**, all now in `mcp.md`, grouped read
  / control / steer / destructive as the hub groups them:
  - run evidence: `get_artifact`, `get_run_log`, `get_phase_logs`, `get_run_diff`,
    `list_proofs`, `get_run_spend`, `query_events`;
  - finding tickets: `search_issues`, `get_issue`, `mark_ready`, `assign_ticket`,
    `pin_provider`, `archive_ticket`;
  - queue control: `run_queue_item`, `stop_queue_item`, `resume_queue_item`,
    `stop_queue`, `acknowledge_drift`;
  - recovery: `address_review`, `advance_run`, `settle_adr_conflict`;
  - QA: `approve_qa`, `reject_qa`, `qa_accounts_list|add|remove`;
  - ticket secrets: `set_ticket_secret`, `unset_ticket_secret`, `list_ticket_secrets`;
  - operator checklist: `get_checklist`, `add_checklist_item`,
    `update_checklist_item`, `delete_checklist_item`;
  - config, prompts and lessons: `set_config`, `list_prompts`,
    `set_prompt_override`, `clear_prompt_override`, `list_lessons`, `add_lesson`;
  - connections: `list_connections`, `test_connection`, `remove_connection`.
  - Diagnosis now starts from these tools; `trau forensics` is the shell fallback.
- **Install and update need no key.** `curl -fsSL https://get.trau.sh/install.sh |
  sh` installs to `~/.local/bin`; the hub's lock screen starts the 14-day trial or
  takes a key. Documents the four license states (`trial`, `licensed`, `grace`,
  `locked`), the locked-installation refusal, and `trau license trial|portal|
  installs|release`.
- **New CLI coverage:**
  - `trau adr authorize|keep`, `trau config set`, `trau qa accounts
    list|add|remove|discover|check`, `trau proofs write-test`;
  - `trau browser status|check|setup`, `trau skill show|export|status|check|install`;
  - `trau connect linear|jira|bitbucket`, `trau connections`, `trau ssh recover`,
    `trau crashreport`, `--complexity-band`;
  - doctor's verdict line and its three check groups.
- **New recipes in `operations.md`:**
  - QA: the hold (`awaiting-qa` frees the lane; the verdict is the user's), sign-in
    accounts, and where proofs go and how long they are kept;
  - ADR-conflict settlement, the local-merge-held pause, and the standing drain
    (`QUEUE_AUTO_DRAIN`);
  - webhook intake (`HOOK_*_SECRET`), service connections (OAuth for Linear, Jira and
    Bitbucket; `gh` for GitHub), the operator checklist, prompt overrides and lessons;
  - keeping this skill current (`SKILL_UPDATE_CHECK`, and trau's embedded copy vs
    this one).
- **Safety rules widened in `SKILL.md`:**
  - The destructive list now matches the hub's own 23-tool group.
  - It names what arms a drain besides `start_queue`: `approve_qa`/`reject_qa`,
    webhooks, and `QUEUE_AUTO_DRAIN`, which `pause_queue` does not hold.
  - Some decisions are the user's alone: the QA verdict, ADR conflicts, drift.
  - Settings that change what leaves the machine are set only when asked:
    `AI_ASSESSMENT`, `EXPERIMENTAL_*`, `TWG_ENABLED`, prompt overrides.
  - A locked install starts no new work.
- **Vocabulary:**
  - New hold gates `daily-cap`, `license` and `idle`, and gates split into waits /
    waits on a person / symptoms.
  - New `no-change` status and `no_change` class.
  - New pause reasons `adr_conflict`, `adr_dir` and `local_merge_blocked`.
  - `branch_held` is only a display label now; the pause reason is `worktree_held`.
- **Config:** `ADR_POLICY`/`ADR_DIR`, `AI_ASSESSMENT`, `MODELS_BY_COMPLEXITY` and
  `COMPLEXITY_*`, `PICK_LABELS`, `BROWSER_HARNESSES`, `QUEUE_AUTO_DRAIN`, `HOOK_*` /
  `SENTRY_*`, `HUB_PEER_*`, `SKILL_UPDATE_CHECK`, `TWG_*`, and the `*_CONNECTION` /
  `*_OAUTH_*` keys; hub-created Projects start on `TRACKER_PROVIDER=internal`.
- **Removed from trau, removed here:** `TEAM_SYNC` (git-ref team sync), the plugin
  system (`PLUGINS`, `.trau/plugins`), the single-value `BROWSER_HARNESS`, and video
  and trace proofs (screenshots only). "There is no `trau config set`" and "no MCP
  tool for the QA verdict" are no longer true.

### 1.2.0
- **Re-documented against trau v2.53.0** (main at 2026-09-05; the skill was written
  against 2.34). Every tool, flag, key, status, gate and class was re-traced to the
  shipped source and the 21 ADRs (0054–0074) landed since; SKILL.md now names the
  version it describes.
- **Install is license-gated.** Homebrew, Scoop and winget are retired and frozen at
  v2.39.0; the path is `curl -fsSL https://get.trau.sh/install.sh |
  TRAU_LICENSE_KEY=<key> sh`, then `trau license set|status`, `trau update
  [--check]` and Settings → Updates (ADR 0062). A `trau --version` ≤ 2.39.0 is the
  stale-install tell.
- **The recovery ladder is inverted.** `resume_run` / `trau --resume <ID>` now
  re-enters a *quarantined* run from whatever its checkpoint durably holds (PR →
  `pr_open`, commit → `verified`, branch → `built`) and un-quarantines the tracker;
  `requeue_ticket` / `trau --requeue` is the start-fresh path, and the CLI form now
  puts the hub queue row back to `pending` itself. `trau takeover` corrected: it
  resumes a *parked* ticket and refuses while a run is live — it never stops one.
- **Quarantine is not "verify tried twice" any more.** `MAX_BUGFIXES` and
  `MAX_ITERATIONS` default to unlimited; the give-up causes are review rounds
  exhausted on a ticket PR (`MAX_REVIEW_ROUNDS` default 10), CI red after repairs,
  a closed PR, unsyncable conflicts or a budget cap. A cap exit with children left
  is the new `capped` class, re-queued, not quarantined.
- **Folder repos run lanes and take epics.** Under `WORKTREES=1` a ticket with a
  `Repo: a, b` first line runs isolated — one linked worktree, app and lane database
  per declared child, unlimited lanes — and a ticket declaring no child is refused
  up front; an epic pinned to one child runs in that child's checkout (ADR 0057), an
  unpinned one runs as a sequential group (ADR 0058). Replaces "a Folder repo runs
  no worktrees and refuses an epic".
- **Review trust is a ladder, not a Bitbucket ADMIN grant** (ADR 0064):
  `TRUSTED_REVIEWERS` → private repo → membership → permission API → unknown, and
  unknown *parks* `awaiting-changes` until someone vouches. Adds `REVIEW_RESOLVE`,
  review rounds and `REVIEW_GATE` on epic PRs, the `address-review` REST path.
- **Vocabulary corrected in `states.md`:** `awaiting-pick` and `PICK_ROUNDS` are
  gone (ADR 0059); `skipped` means a duplicate of an epic child queued ahead, not an
  `on_fault=skip` fault (those settle `failed`); the `parked-epic` gate is `parked`
  and covers parked tickets; new `team-drift` gate; `parked` is a defined set
  including the unfinalized epic (ADR 0062); the failure classes (`stopped`,
  `capped`, `requeued`, …) and the 13 pause reasons (`tool_unavailable`,
  `forge_outage`, `commit_probe_failed`, …) are tabled for the first time, along
  with the `releasing` / `awaiting-qa` phases and instance session states.
- **Four new MCP tools:** `add_project_repo`, `reveal_secret` (hidden from
  `tools/list` until a repo sets `SECRET_REVEAL=admin`; mandatory reason; audited),
  `list_deleted_tickets` and `restore_ticket` (a deleted ticket leaves a tombstone
  that blocks every later sync). `start_queue acknowledge_drift`, `get_run ref=<run
  URL>` (ADR 0056), `create_ticket blocked_by / blocks / repos`, richer
  `list_repos` / `queue_status` / `list_worktrees` payloads, REST method
  corrections, and a warning that `…/secrets/resolve` is unaudited.
- **New CLI coverage:** `trau secret set|unset|list|get`, `trau worktree init`,
  `trau forensics log` (the child's console — the one on-disk run artifact),
  `config get --reveal`, `config export|import --section`, `test-setup --child` on
  folder repos, `--skip`, `--qa-gate`; doctor's real check set (*team config*,
  *review trust*, *worktree file*, *serena*, *license*, *crash reports*, …).
- **Config: lanes and files.** Per-lane databases are trau's job (`WORKTREE_DB`,
  ADR 0070), a committed `.trau/worktree.yaml` replaces `WORKTREE_COPY` /
  `WORKTREE_SETUP_CMD` / `APP_SERVE`+`APP_START_CMD` per section, and
  `.trau/config.team.ini` drift on merge-affecting keys fails doctor and blocks the
  drain. Adds `auggie` (USD caps never fire on it), `SECRET_REVEAL`,
  `TRAU_LICENSE_KEY`, `CRASH_REPORTS`, `NOTIFY` / `HOLD_REMINDER_HOURS`, `PLUGINS`,
  `SERENA`, `EPIC_ADOPT_PARENT`, `BROWSER_ISOLATION`, `CLAUDE_OUTPUT_STYLE`, phase
  routes re-resolved per agent call (ADR 0069), presets (ADR 0063).
- New operations recipes: install/upgrade, ticket secrets, plugins, notifications,
  workspaces (ADR 0073 — a UI grouping, not `SERVE_WORKSPACE`), support bundle vs
  crash reports; the babysitting brief and hard stops now cover secrets.

### 1.1.0
- **Re-documented against trau 2.34.** Every tool, flag, config key, status and gate
  in the skill is now traced to the shipped source; the stale ones are gone.
- **Five new MCP tools**, taking the reference to every tool the hub's `tools/list`
  declares: `resume_run` (a settled row back to pending from its checkpoint, no
  phase re-run), `requeue_ticket` (the quarantine undo over MCP), `retry_release`
  (an epic parked at `awaiting-merge` handed back), `get_config` (resolved config
  with layers, secrets masked) and `list_worktrees` / `get_costs`.
- **`steer_agent kind=keys`**: whitespace-separated key names typed raw into a live
  terminal dialog, landing only in a session already running and expiring 30 seconds
  after queueing.
- **Hold vocabulary is real now.** `queue_status` carries `held_gate` beside
  `held` / `held_reason` / `held_since`, and the ten gates are split into deliberate
  waits and symptoms. The QA gate turns out not to be a hold at all — it is the item
  status `awaiting-qa`.
- **Config lives in the hub database.** The user and project layers are rows
  (ADR 0051), not `~/.trau.ini` and `<repo>/.trau.ini`; `./trau.ini` is the last file
  layer. Adds `trau config get / export / import`, and says plainly that secrets are
  stored clear-text with file permissions as the only boundary.
- **No lane cap.** `WORKTREE_PARALLEL` is gone (ADR 0047): a worktree repo runs every
  eligible queued ticket at once, and the spend caps are the only throttle.
- **Run data is not on disk.** `.trau/runs/**`, `build.log` and `*.pty.log` are
  removed throughout — checkpoints, artifacts, phase logs, events and transcripts are
  hub-database rows (ADR 0008), read through `get_run`, `trau forensics` and the web
  Run detail.
- **New `references/states.md`**: queue item statuses, hold gates, pause classes and
  run phases as tables, each with what an operator should actually do.
- New operations recipes: the review feedback loop (`REVIEW_GATE`, bounded fix rounds,
  `awaiting-changes`), halts and the hub's Unblock prompt, epics and parked epics,
  Publish sessions, config sharing, and `trau dump`.
- New CLI coverage: `dump`, `config …`, `hub remote` (Tailscale Serve — no token, the
  bind stays loopback), `worktree test-setup`, `--retry-release`, `--parent`,
  `--worktree`, `--no-serve`; `trau watch` corrected — it takes no path.
- Auth: state-changing routes refuse cross-site browser requests on every bind, and
  `SERVE_ALLOW_REGISTER` is a second gate on repo registration off loopback. Also
  warns that the hub's per-session `trau-grill` / `trau-publish` MCP endpoints are not
  the hub MCP.

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
