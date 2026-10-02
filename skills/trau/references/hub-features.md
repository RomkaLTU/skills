# Hub features an operator meets but does not drive

The hub's web UI hosts a few features that have no operator tool for their writes, or
none at all. You will still meet them — a ticket that waits on the App, a user who asks
what the Assistant said, a database question — so this file says what each one is, what
you can read, and what you must leave to the user.

- [Terminal sessions](#terminal-sessions)
- [App page](#app-page)
- [Assistant](#assistant)
- [Data sources](#data-sources)
- [Report-derived Proposed ADRs](#report-derived-proposed-adrs)

## Terminal sessions

The hub's **Terminal** page runs the operator's shells, agent CLIs, named commands and
takeovers as PTY sessions, per repo.

- `list_terminal_sessions` and `read_terminal_screen` read them (`references/mcp.md`
  has the fields). Name a session to the user by its `handle` — a permanent
  adjective-noun name such as `brave-otter` that the user sees beside the session name
  and a process in the session reads from `TRAU_TERMINAL_SESSION`.
- A Claude Code or Codex agent session gets its own read-only endpoint,
  `POST /api/v1/terminals/{id}/mcp`, with `list_terminal_sessions`,
  `read_terminal_screen`, `list_runs`, `list_instances` and `queue_status`, and a note
  with its handle. There `repo` defaults to the session's repo and its own row has
  `self: true`. The agent checks the other sessions and runs before it changes files,
  and asks the user when the request collides with work in progress.
- No tool types into a session, or opens, restarts or ends one. Ask the user to do it
  on the Terminal page.
- A failed exit, an exit after 10 seconds or more of work, or a request for input
  raises a Terminal outcome in the hub's notification center (`terminal_outcome`). No
  tool marks it seen.
- Off the machine (a non-loopback bind or the tailnet) both tools answer
  `terminal_not_exposed` unless the hub sets `SERVE_ALLOW_TERMINAL=1`. Never set that
  key yourself: it lets a remote client open a shell with the hub's user rights.
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
  That is not a fault. Do not requeue, reset or quarantine the ticket; ask the user to
  stop the app on the App page, or to turn on worktrees so the ticket runs in its own
  lane. Ticket cleanup never stops the App session.
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
page opens its panel, where the user starts a **Conversation** about a Repo (and
optionally a ticket); its state is `open`, `running`, `waiting` (it asked the user
something) or `resolved`.

- **It is not yours to drive.** When the user asks what it said, its Conversations are
  at `GET /api/v1/assistant/threads`. When the user asks *you* to watch a drain or clear
  a halt, use this skill's tools — the hub no longer hands out a watch or unblock prompt
  to paste into a terminal agent.
- It reads the hub through the read tools, and runs `steer_agent`, `pause_queue`,
  `start_queue` (halting on a fault), `move_queue_item`, `resume_run`,
  `resume_queue_item`, `requeue_ticket` and `acknowledge_drift` on its own, posting each
  as an action. It only *proposes* `run_queue_item`, `stop_queue_item`,
  `stop_instance`, `retry_release`, `set_config` and `create_ticket`; the user applies or
  declines each in the panel. `ASSISTANT_MAX_ACTIONS` (default `10`) caps the actions of
  one Conversation; past it, it only advises until the user raises the budget.
- **It opens Conversations itself on incidents** (ADR 0164): a run that pauses (not on
  `reauth` or `usage_window`), faults, gives up or parks its epic; a queue row the drain
  pauses; a repair stall; a hub handler panic; and three stall detectors —
  `drain_idle` (an armed drain with runnable work starts nothing for
  `ASSISTANT_STALL_MINUTES`), `presence_lost` (no loop heartbeat for 10 minutes) and
  `repair_loop` (three verify rounds failing with the same summary). A halt on the Queue
  or run page offers **Ask the Assistant**, which opens that incident's Conversation.
- When it concludes a problem is a trau defect it drafts a report for the maintainers
  (version, platform, the failure, recent events and log lines, its diagnosis and
  actions — secrets masked, no transcript, attachment or config value).
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
  the repo sets `DATA_ASK_SAMPLES=on`, which lets it read the rows its SQL returns, so
  those values reach the model vendor. Change that key only when the user asks. On an
  `mssql` source the agent writes T-SQL, and the hub gates every statement first.
- Export and search limits are config keys (`DATA_EXPORT_ROW_CAP`,
  `DATA_EXPORT_TIMEOUT`, `DATA_SEARCH_TABLE_TIMEOUT`, `DATA_SEARCH_TIMEOUT`,
  `DATA_SEARCH_ROW_LIMIT`); `trau config describe <KEY>` gives each default. An export
  that stops at a limit says so in its last line.

## Report-derived Proposed ADRs

On an open finished or applied Report, **Draft an ADR** starts a separate interview in
the Report's Repo: the user selects one durable decision, reviews the complete Proposed
record and its target path, and approves the save. The source Report and existing ADRs
stay unchanged, and approval neither accepts nor implements the decision — nor does it
authorize any run (that is still `settle_adr_conflict`). The hub alone writes to
`ADR_DIR`. This is a hub UI flow with no operator MCP or CLI equivalent.
