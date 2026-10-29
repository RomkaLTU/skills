# Hub features an operator meets but does not drive

The hub's web UI hosts features that have no operator tool for their writes, or none at
all. You will still meet them — a ticket that waits on the App, a user who asks what the
Assistant said, a Sentry issue on the Monitoring page, a calibration proposal — so this
file says what each one is, what you can read, and what you must leave to the user.
Every section ends in the rule it implies; when in doubt, the user decides.

- [The Cobble name](#the-cobble-name)
- [Terminal sessions](#terminal-sessions)
- [App page](#app-page)
- [Assistant](#assistant)
- [Data sources](#data-sources)
- [Monitoring](#monitoring)
- [Calibration](#calibration)
- [Lessons, team lessons and promotions](#lessons-team-lessons-and-promotions)
- [Conformance results and re-verify](#conformance-results-and-re-verify)
- [Hosted mode and collaborators](#hosted-mode-and-collaborators)
- [Prototypes](#prototypes)
- [Backlog goals](#backlog-goals)
- [The Demo](#the-demo)
- [Report-derived Proposed ADRs](#report-derived-proposed-adrs)
- [Prepare, session history and maintainer cards](#prepare-session-history-and-maintainer-cards)

## The Cobble name

**Cobble** is the product's display name in the hub UI, the TUI header and notification
titles (ADR 0201). trau stays the technical name: the binary, commands, config keys,
paths, storage keys, URLs and every wire value (states, gates, classes, tool names). When
you talk to the user about what they see on screen, say Cobble; when you name a command,
key or value, keep `trau`. The hub has **one web layout** (ADR 0348): the Tickets layout
and its switch are gone and `WEB_LAYOUT` is a retired key — never tell a user to switch
layouts.

## Terminal sessions

The hub's **Terminal** page (also a dock and a pop-out window beside other pages) runs
the operator's shells, agent CLIs, named commands, saved Servers and takeovers as PTY
sessions, per repo.

- `list_terminal_sessions` and `read_terminal_screen` read them (`references/mcp.md`
  has the fields). Name a session to the user by its `handle` — a permanent
  adjective-noun name such as `brave-otter` that the user sees beside the session name
  and a process in the session reads from `TRAU_TERMINAL_SESSION`.
- A Claude Code, Codex or Copilot agent session gets its own read-only endpoint,
  `POST /api/v1/terminals/{id}/mcp`, with `list_terminal_sessions`,
  `read_terminal_screen`, `list_runs`, `list_instances` and `queue_status`, plus
  session-only `read_previous_conversation` for Continue, and a note
  with its handle. There `repo` defaults to the session's repo and its own row has
  `self: true`. The agent checks the other sessions and runs before it changes files,
  and asks the user when the request collides with work in progress.
- **No confirmations.** The New session menu offers each agent preset also as
  *<Provider> · no confirmations*: the session runs every tool call without asking, in
  this checkout (`--dangerously-skip-permissions` for Claude Code, the bypass flags for
  Codex, Copilot, Kimi and Auggie). The browser remembers the pick per provider, and such
  a session shows a **no confirmations** badge. It is the user's per-session choice — never
  suggest it to get past a prompt, and treat such a session as one that can change the
  checkout at any moment.
- **Saved Servers.** A saved Server opens an ssh session; its password is sealed with the
  hub key and typed once at the OpenSSH password prompt (ADR 0320), never shown or
  logged. Never ask the user to paste a server password into a chat.
- No tool types into a session, or opens, restarts or ends one. Ask the user to do it
  on the Terminal page.
- A failed exit, an exit after 10 seconds or more of work, or a request for input
  raises a Terminal outcome in the hub's notification center (`terminal_outcome`). No
  tool marks it seen.
- Off the machine (a non-loopback bind or the tailnet) both tools answer
  `terminal_not_exposed` unless the hub sets `SERVE_ALLOW_TERMINAL=1`. Never set that
  key yourself: it lets a remote client open a shell with the hub's user rights. A
  hosted Collaborator never gets the Terminal.
- `trau doctor` times the login shell that starts each agent session on its
  `terminal shell` line; `start_note` on a session says where the time went when an
  agent showed its first output 3 s or more after the start.

## App page

The App page (`/app`) starts the repo's reviewed services and preparation steps without
a ticket (ADR 0162): services in dependency order, the selected preparation (installs,
builds, migrations) in its reviewed order, and workers that are ready once their
process runs. **No MCP tool or CLI command** saves its plan, starts, stops, restarts or
reruns it, or sets an App setting — send the user to the page.

- **It holds the checkout.** While an App session runs, a ticket that would run in that
  checkout, or change it, waits: the run log says `waiting for <checkout>`, the Loop
  page shows `Waiting on the App`, and `queue_status` reports `held_gate: app-session`.
  That is not a fault. Do not requeue, reset, discard or quarantine the ticket; ask the
  user to stop the app on the App page, or to turn on worktrees so the ticket runs in its
  own lane. Ticket cleanup never stops the App session, and the hosted repository refresh
  skips a checkout an App holds.
- **Docker Compose.** The page imports a local Compose setup the user picks (files,
  profiles, services); a Compose service runs as `compose.<service>`. Trau uses the
  installed docker CLI and never installs Docker, edits a Compose file, recreates a
  container or removes a volume. When Start says the Compose setup changed, the user
  reviews the update on the page; never tell them to bypass it.
- **Local database or cache.** When the repo's settings need one, the page offers a
  local PostgreSQL, MySQL, MariaDB or Redis service (`local.db`, `local.cache`) through
  Compose, after the user accepts its recipe: pinned version, port on 127.0.0.1,
  credentials generated once, a data volume nothing removes. When the repo's `.env`
  already names a database, the user chooses to reuse it or start a local one — do not
  choose for them.
- **Local WordPress.** An unconfigured WordPress repo can run on a managed `wp-env`
  runtime (ADR 0244). It needs Node.js and Docker, never a local PHP; its `admin` /
  `password` login is local-only. Never accept the `wp_env` setup for the user.
- **Folder repos** run the Child repos the user selects as one app (`api/web`, with
  cross-child bindings such as `api/web:url`). When Start names another App session
  that holds a Child checkout, the user stops that session or drops the Child from the
  plan; do not stop it for them.
- **Advice.** The page can ask a Claude agent about gaps detection left. The agent has
  no tools, sees manifests, scripts and setting names but never a secret value, and
  answers with a diff the user accepts item by item. It never selects a migration or a
  seed; do not treat its draft as a reviewed plan.
- A migration, seed or script Trau cannot read runs only when the user selected it —
  never tell the user to select one. App setting values are write-only and never reach
  an agent, so never ask the user to paste one into a chat.

## Assistant

The Assistant is the Supervisor the hub hosts itself (ADR 0162). A launcher on every hub
page opens its panel (dockable into the sidebar), where the user starts a
**Conversation** about a Repo (and optionally a ticket); its state is `open`,
`running`, `waiting` (it asked the user something) or `resolved`.

- **It starts only when the user starts it** (ADR 0319). The hub opens no incident
  Conversation and runs no turn on its own — the stall detectors, triage turns and
  automatic defect reports are gone, and `ASSISTANT_STALL_MINUTES` is retired. A halt's
  **Ask the Assistant** button only opens the new-Conversation composer with a first
  message naming the ticket, halt and reason; nothing runs until the user presses Send.
  A hub restart moves a running Conversation back to `open` with *Try again*.
- **It reads on its own and proposes every write** (ADR 0318). There is no reversible
  tier any more: every hub write is a **Proposal** card (tool, arguments, why) or a set of
  two to four **Alternatives** with an optional recommendation (ADR 0342), and the tool
  runs only when the user presses Apply or picks one. A set settles once — one pick or
  Decline all. It never receives QA approval, secret, connection removal, account
  removal or hub restart tools. `ASSISTANT_MAX_ACTIONS` (default `10`) counts applied
  Proposals only; at the cap it is advise-only until the user raises that
  Conversation's budget.
- **It is not yours to drive.** When the user asks what it said, its Conversations are
  at `GET /api/v1/assistant/threads`. When the user asks *you* to watch a drain or clear
  a halt, use this skill's tools and its authorization rules — never apply or pick an
  Assistant Proposal on the user's behalf.
- In a user Conversation it can draft a report for the maintainers when it concludes a
  problem is a trau defect (version, platform, the failure, recent events and log lines,
  its diagnosis and actions — secrets masked, no transcript, attachment or config value).
  `ASSISTANT_REPORTS=1` sends it at once; off, the user presses Send.
- Delete in the panel removes one Conversation's messages, proposals, history and
  drafts for good. It is not a rollback: applied actions stay applied. No tool or
  command deletes a Conversation.
- Its keys (`ASSISTANT`, `ASSISTANT_PROVIDER`, `ASSISTANT_MODEL`, `ASSISTANT_EFFORT` and
  the advanced ones) are hub-wide — user layer and hub environment only; the user sets
  them in Settings → Assistant. Its spend lands in the `_assistant` bucket.

## Data sources

A Data source is a read-only database registration of a repo that the Data page reads
in the hub process (ADR 0146). `list_data_sources` and `describe_data_source` are the
operator's reads; they never return a password or a row value.

- Engines are `sqlite`, `pgsql`, `mysql` and `mssql`. An `mssql` source is a
  `sqlserver://login:password@host:1433?database=name` URL with a SQL login. It has no
  writable-credential override: the hub registers it only when the login proves it can
  only read, re-proves that at every open, and refuses `accept_writable` (ADR 0198).
  When a proof fails, point the user to the least-privilege login in
  `docs/data-mssql.md` of the trau source.
- Adding or deleting a source, asking a **Question**, exporting a table (CSV or JSON
  Lines) and searching a source for a text are Data page flows; no MCP tool does them.
  The Add dialog detects the development database from `WORKTREE_DB_URL` and the repo's
  `.env` without connecting to it, else asks the repo's active Provider to name it.
- A Question runs a headless agent that sees the schema and row counts only — unless
  the repo sets `DATA_ASK_SAMPLES=on`, which lets it read the rows its SQL returns
  (capped at `DATA_ROW_CAP`), so those values reach the model vendor. Change that key
  only when the user asks. On an `mssql` source the agent writes T-SQL, and the hub gates
  every statement first.
- Export and search limits are config keys (`DATA_EXPORT_ROW_CAP`,
  `DATA_EXPORT_TIMEOUT`, `DATA_SEARCH_TABLE_TIMEOUT`, `DATA_SEARCH_TIMEOUT`,
  `DATA_SEARCH_ROW_LIMIT`); `trau config describe <KEY>` gives each default. An export
  that stops at a limit says so in its last line. A hosted Collaborator never reaches
  Data sources.

## Monitoring

The **Monitoring** page connects a vendor source per repo and turns its issues into
work (ADR 0278, 0284). Sentry is the only source: the user saves `SENTRY_API_TOKEN`
(secret; `event:read`, `project:read`, `org:read`, plus `event:write` to resolve),
`SENTRY_ORG`, `SENTRY_PROJECTS` (a slug belongs to one repo per org) and optionally
`SENTRY_QUERY` (default `is:unresolved`), `SENTRY_BASE_URL` and `SENTRY_POLL_INTERVAL`
(default 5m) on that page. No MCP tool reads or changes Monitoring items.

- **`SENTRY_MODE=draft`** (default): each poll records every issue first seen after the
  connect as a **new** item, nothing more. The user presses **Start** (a draft Interview
  on Prepare, opened from the issue's current detail, with a Sentry chip) or
  **Dismiss**. **Import** brings in up to 100 existing open issues as new items on request.
- **`SENTRY_MODE=auto`** creates and runs the Interview itself, one at a time per repo,
  and on a `create` outcome approves it under the Operator identity — the one case
  where an Interview's writes are approved without a person — files the ticket with the
  ready, `bug` and `sentry` labels, queues it and arms the drain. An Interview that asks
  without a recommended answer, stalls or proposes anything else waits on Prepare with
  a `monitor_attention` notification. Imported items never auto-start.
- An issue resolved upstream leaves the page; a closed or resolved one returns as new
  when Sentry reports new events (`monitor_reopened`); a dismissed one returns only when
  Sentry calls it regressed or escalating. Once the ticket's fix is merged and the issue
  stays quiet for `SENTRY_RESOLVE_AFTER` (default `24h`, or `off`), the hub resolves it in
  Sentry.
- The push-based `/hooks/sentry` webhook is a separate intake (`references/operations.md`
  § Webhook intake); a hook-filed issue is recorded `filed`, never drafted twice.

Rule: `SENTRY_MODE=auto` is unattended spend and unattended approval — set it only when
the user asks. Start and Dismiss are the user's. Never ask for or paste the Sentry token.

## Calibration

The **Calibration** page turns run evidence into bounded, reversible config proposals
(ADR 0329, 0334, 0336).

- A **daily read-only sweep** (hub start, then every 24 h; the page's Refresh runs one
  repo) writes a snapshot per repo: first-pass verify rate, repair rounds, repair spend
  share, cost percentiles per phase family, outcome per band and Preset, open High usage
  findings (judged against the repo's own p90 baseline, ADR 0337) and recurring failure
  classes. It calls no tracker, forge, network or agent. `calibration_report` serves it.
- From the snapshots a versioned rule table proposes **at most one change per repo and
  key in 14 days**, only for whitelisted keys: `COMPLEXITY_LOW_MAX`,
  `COMPLEXITY_HIGH_MIN`, the `<PROVIDER>_COMPLEXITY_<BAND>_PRESET` keys, `MAX_REPAIRS`,
  `MAX_BUGFIXES`, `TEST_EFFORT` and the effort / Model Routes of the build, handoff,
  repair, bugfix, cleanup, lintfix and commit phases — never `VERIFY_EFFORT`, a verify
  Route, a cost cap, a credential or a delivery key. Each new proposal raises a
  `monitor_attention` notification.
- `list_calibration_proposals` lists them (`open`, `watching`, `kept`, `reverted`,
  `dismissed`, with evidence and expected effect). `decide_calibration_proposal
  decision=apply` writes the project layer like Settings does and **watches the next 20
  completed runs**: if first-pass verify or conformance pass rate falls more than 5
  points, or the PR changes-requested rate rises more than 5, the hub writes the old
  value back and notifies. `decision=dismiss` silences that key and direction for 90
  days.
- `CALIBRATION_AUTO_APPLY` (hub-wide, off) lets the sweep apply cost-down steps of
  `MAX_REPAIRS`, `MAX_BUGFIXES` or a phase effort by itself; everything else waits.

Rule: never apply or dismiss a calibration proposal, and never turn on
`CALIBRATION_AUTO_APPLY`, without the user's word — each changes how every later run is
routed.

## Lessons, team lessons and promotions

The **Lessons** page is the ledger the loop learns from (ADR 0283, 0335).

- **Distill.** With `LESSONS_DISTILL=1` (default) a verify that passed only after a
  repair, or a quarantine, gets one cheap agent pass that writes a takeaway (≤240
  characters), a kebab-case **class** and the paths the fix touched; it runs outside the
  run's budget and never changes the outcome. A lesson it did not classify carries
  `<failure type>-unclassified`. Recall gives a run at most five lessons and records
  them (`LESSONS_RECALLED`). The page's reclassify pass runs one agent call per
  unclassified lesson (up to 100) — only when the user asks.
- **Team lessons.** `TEAM_SYNC=1` (per repo, project layer, off by default) publishes
  this hub's lessons — known secrets masked, pattern matches left out — to
  `refs/trau/lessons/<install-id>` on the repo's own remote and merges teammates' refs
  into the Lessons page, `list_lessons` and recall (each with `author` / `me`). Turning
  it on runs one full sync first and is refused with the remote's reason (also for a
  Folder repo or a repo without a remote); turning it off removes every teammate lesson
  and deletes this hub's ref. Doctor's *team lessons* line shows sync failures; they
  never touch a run. A stale `TEAM_SYNC=1` from the retired run-sharing feature counts
  as on.
- **Promotions.** Three lessons of one class in 30 days open one proposal to add a rule
  line under `## Lessons promoted by Trau` in the repo's `AGENTS.md` (a Monitor item and
  `monitor_attention`). `list_lesson_promotions` reads them; `apply_lesson_promotion`
  commits on `trau/lesson-<class>` and opens a PR (a Folder repo or a remote-less repo gets
  the file written in place); `dismiss_lesson_promotion` needs a reason and silences the
  class for 90 days.

Rule: `TEAM_SYNC` sends lessons to a shared remote — turn it on only when the user asks.
Apply or dismiss a promotion only on the user's word; it changes the instructions every
later agent reads.

## Conformance results and re-verify

After an epic is done, one **conformance pass** grades the merged base in its own lane
against the decision-board picks, the Interview's clarifications and the epic acceptance
criteria (ADR 0305); it never blocks, reopens or re-statuses the epic. The run page
shows the deviation list (`get_artifact kind=conformance`), the earlier passes, and one
**File fix ticket** per pass; deviations the user leaves out of that ticket count as
accepted on later passes (ADR 0306). **Re-verify** on the run page, `reverify_run` or
`trau run reverify <ID>` runs the pass again on a shipped epic or ticket. Details:
`references/states.md` § Conformance results, `references/operations.md` § Conformance
and re-verify.

Rule: a re-verify costs an agent call and a fix ticket files tracker work — both only
when the user asks. A deviation is a finding to report, not a reason to reopen, requeue
or discard the epic.

## Hosted mode and collaborators

A **hosted** hub is one client environment behind a reverse proxy (`SERVE_PUBLIC_URL`
set — a Cloudflare Tunnel, or the client's own proxy with `SERVE_TRUSTED_PROXIES`;
ADR 0249, 0250, 0349). Every forwarded request needs the operator token or a
**Collaborator** session; agent processes run as a second uid and never read the hub's
secrets (ADR 0350).

- **Collaborators** are people the Operator issues a token to: `trau collaborators add
  <name> <email> [--role business|technical]` prints the token **once**, so only the user
  runs it, on the hub's machine. `trau collaborators list [--json]` shows them and
  `seats: <active>/<N>` (`revoke <id>` ends that person's session at once — confirm
  first). A Collaborator holds one session (2 h idle, 7 days max, a second sign-in ends
  the first). A collaborator token travels only through the client's own channel — never
  in a URL, ticket or log.
- **Seats.** Each active Collaborator holds one seat of the license key; an add past the
  count fails `seats_exhausted` until someone is revoked (ADR 0251, 0254).
- **Roles** (ADR 0333). `business` (default) starts and approves Business specifications
  only. `technical` also starts and approves Technical specifications and Research, reads
  the Queue, Runs and Monitoring, queues tickets, starts and stops the drain and steers
  runs. A role change on Settings → Collaborators ends the session. Everything off the
  role's allow-list answers `403 collaborator_restricted`; never hand anyone the operator
  token to get past it.
- **Personal connections.** A Collaborator enters their own Claude, Codex or DeepSeek key
  or subscription sign-in, their own Linear / Jira credential, and (Technical) their own
  GitHub account on **Account and connections**, sealed with `ACCOUNT_SECRETS_KEY`. None
  falls back to the hub's credentials. A row they queue runs as them (`queued_by`, ADR
  0331); a lapsed connection pauses the run `connection_lost`. With the operator token,
  `GET` / `DELETE /api/v1/personal-accounts`, `/personal-connections` and
  `/personal-forge-connections` list and revoke them — confirm before any revoke.
- **Setup.** `trau hosted status <record.yaml>` and `GET /api/v1/hosted/status` change
  nothing and list each prerequisite with its next action. `trau hosted setup` (creates
  Fly / Cloudflare resources, prints tokens once) and `trau hosted deploy` (builds and
  restarts client hubs) are the user's to run. The repository refresh keeps hosted
  checkouts current (`references/operations.md` § Hub lifecycle and exposure).

Rule: never add, revoke or re-role a Collaborator, change seats, or revoke a personal
account or connection without the user's word. Never ask for, relay or copy anyone's key,
token, sign-in code or CLI auth file, and never print, rotate or unset
`ACCOUNT_SECRETS_KEY`. Never answer a Collaborator's `409` (`connection_required`,
`personal_connection_missing`, `turn_busy`, `approval_bound`) by acting with the operator
token.

## Prototypes

The **Prototypes** page holds clickable, throwaway multi-page mockups in the product's
look (ADR 0344). A prototype is a grill session in `prototype` mode whose one **bundle**
artifact improves in versions, one per turn with a changelog line; a set can carry two to
four **Variations** with one pick, which is a decision-board pick that verify and the
conformance pass later grade against. It runs read-only on `PROTOTYPE_PROVIDER`
(default `claude`) and `PROTOTYPE_MODEL` (default `sonnet`), never writes into the repo,
never settles and is never a Prepare item. **Promote** files (or later updates) one epic
that links the prototype; **Archive** only hides it. A share link is an opt-in anonymous
route. No MCP tool drives it.

Rule: Promote, the Variation pick and sharing a link are the user's decisions — Promote
files tracker work and a share link exposes the prototype to anyone holding it.

## Backlog goals

A **Backlog goal** is the Operator's saved focus for one repo or one Workspace (ADR
0291): a text of at most 2,000 characters and up to 30 match terms, saved from the
Backlog's **Suggest next task** panel. A term hits a task by label, ticket-key prefix
(`PAY-`) or whole word in its title or description; a sub-issue takes its epic's hits.
The **Suggested order** pass ranks matched tasks first, matched rows show a **Goal**
badge, and the **Matches goal** filter keeps only them. A repo with no goal uses its
Workspace's. Each Suggested order keeps the goal it read. The goal is hub data only — it
never reaches the tracker or the queue — and only the Operator reads or writes it
(`GET` / `PUT /api/v1/repos/{repo}/backlog-goal`, web-only; no MCP tool). The order pass
runs on the user's own Provider (`<PROVIDER>_TASK_ORDER_MODEL` / `_EFFORT`).

Rule: the goal and the suggested order are advisory. Do not change the goal unless the
user asks, and never queue tickets from a suggested order without their word.

## The Demo

A **Demo** is a disposable, isolated hub (default `:8790`, its own demo home and repo)
that plays a Scenario through the real pipeline with a scripted agent — no Provider, and
except for a live Demo no `gh` or network. It never touches the everyday hub. A
maintainer makes and starts one from a trau source checkout (`trau demo start|play|
status|reset|list|export`); anybody opens a **Demo file** on any build with
`trau demo import <file>` or *Open a Demo file* in Settings (ADR 0323). In the everyday
hub the **Demo** card now lives on its own **Demo** page in the sidebar's OPERATE group,
listed only while the selected repo is the trau source repo and `gh` can read the private
releases repo; it starts, paces, pauses, exports and resets the Demo.

Rule: start, play or reset a Demo only when the user asks — `trau demo reset` stops the
demo hub and deletes the demo home. A Demo's tickets, queue and runs are not real work:
never report them as the user's.

## Report-derived Proposed ADRs

On an open finished or applied Report, **Draft an ADR** starts a separate interview in
the Report's Repo: the user selects one durable decision, reviews the complete Proposed
record and its target path, and approves the save. The source Report and existing ADRs
stay unchanged, and approval neither accepts nor implements the decision — nor does it
authorize any run (that is still `settle_adr_conflict`). The hub alone writes to
`ADR_DIR`. This is a hub UI flow with no operator MCP or CLI equivalent.

## Prepare, session history and maintainer cards

The Prepare page labels Interview as **Technical specification**. Business requirements
Refine can update an existing user story. Review the Apply preview before approving;
see `references/mcp.md` for the REST version check and partial-Apply retry rules.

Previous session lists human-created hub Terminal conversations. It excludes automation
and sessions of unknown origin, including external-terminal sessions. Continue can read
its stored conversation through the session-only `read_previous_conversation` tool;
this is not a hub MCP tool.

The source repo's Publish card runs Publish and a deterministic Hotfix; neither writes
a website changelog any more (ADR 0289). The Demo card is on the Demo page (§ The Demo).
**Settings → Maintainer connection** and **Reports** receive Assistant reports on the
Cobble owner hub; no tool reads them, and a received report files or queues nothing by
itself. There is no operator MCP tool to start any of these, and none of their tokens
belongs in a chat, a ticket secret, a config key or a Checklist input.
