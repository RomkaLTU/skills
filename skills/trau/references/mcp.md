# Trau over MCP

The hub speaks MCP over one streamable-HTTP endpoint — no stdio server to install,
nothing to run beside the hub:

```
POST {origin}/api/v1/mcp
```

`{origin}` is wherever the hub serves — `http://127.0.0.1:8728` by default. The server
names itself `trau`. Every tool calls the same store and drain logic as the web UI and
the CLI, so what you see over MCP and what the Queue view shows can never disagree.

In the hub's web UI, the **Hub** page's *External agents (MCP)* card renders these
same setup snippets with the endpoint already resolved for however the user reached
the hub.

## Auth

The endpoint inherits the hub's exposure policy:

- **Loopback binds are open** — a `127.0.0.1` / `localhost` hub needs no credential.
- **Any other bind requires the serve token** — the hub refuses to start exposed
  without `SERVE_TOKEN`, and every request (MCP included) must carry
  `Authorization: Bearer <token>` or gets a `401` — a browser session may carry it
  as the `trau_serve_token` cookie instead. (`SERVE_TOKEN` is editable from
  Settings like any secret and applies on the next hub restart.)
- **Cross-site browser requests are refused on every bind, loopback included.** A
  state-changing route answers `403 cross-site request blocked` when the request
  carries `Sec-Fetch-Site: cross-site`, or an `Origin` naming a different host than
  the one it was sent to — so a page the user happens to visit cannot fire a
  no-cors `POST` at their hub. Only browsers set those two headers: an MCP client,
  `curl` or the CLI sends neither and is unaffected.
- **Widening where agents run needs a second gate.** Off loopback,
  `SERVE_ALLOW_REGISTER=1` *on top of* the token is required for registering or
  unregistering a repo, `add_project_repo` and the project CRUD, filesystem browse /
  discover / init, tracker test-connection probes and writing `.trau/worktree.yaml` —
  so a leaked token cannot widen the set of directories trau runs agents in.

### The blessed remote path is not an exposed bind

`trau hub remote on` publishes the hub over the user's tailnet with Tailscale
Serve: the URL is `https://<magicdns-name>` on port 443, the hub's own bind stays
loopback, and there is **no token** — only devices signed in to the tailnet can
reach it at all. `trau hub remote status` prints the URL and a QR code.

The `https://<host>:8728` + `Authorization: Bearer` snippets below describe the
*other* path — a genuinely exposed bind. Don't mix them up: a tailnet hub reached
over 443 needs no header. (The token gate only engages on a non-loopback bind, so
setting `SERVE_TOKEN` on a tailnet-published loopback hub changes nothing.)

## Per-session MCP endpoints are not the hub MCP

The hub also serves short-lived, per-session MCP endpoints that have nothing to do
with operating the loop:

- `/api/v1/grill/{sid}/mcp` — server name `trau-grill`, tools `ask_user`,
  `ask_round`, `finish_session`. This is how an Inbox interview talks back to the
  person driving it.
- `/api/v1/grill/{sid}/mcp/{member}` and `…/{member}/{round}` — also `trau-grill`,
  one tool `submit_decision`: a second-opinion panel member's channel.
- `/api/v1/publish/{id}/mcp` — server name `trau-publish`, tools `publish_step`,
  `finish_publish`: the reporting channel of a Publish session.

None carries any of the tools below. An operator agent that finds one of these
connected in its client must not mistake it for the `trau` hub server — check the
server name *and* the endpoint path before assuming a tool exists.

## Connecting a client

### Claude Code

```bash
claude mcp add --transport http trau http://127.0.0.1:8728/api/v1/mcp
```

Token-gated hub:

```bash
claude mcp add --transport http trau https://<host>:8728/api/v1/mcp \
  --header "Authorization: Bearer $TRAU_SERVE_TOKEN"
```

`/mcp` inside Claude Code then lists the server and its tools.

### Codex

In `~/.codex/config.toml`:

```toml
[mcp_servers.trau]
url = "http://127.0.0.1:8728/api/v1/mcp"
```

Token-gated — Codex reads the credential from the environment, not the file:

```toml
[mcp_servers.trau]
url = "https://<host>:8728/api/v1/mcp"
bearer_token_env_var = "TRAU_SERVE_TOKEN"
```

### Generic `.mcp.json` (Cursor and most other clients)

```json
{
  "mcpServers": {
    "trau": {
      "type": "http",
      "url": "http://127.0.0.1:8728/api/v1/mcp"
    }
  }
}
```

Token-gated: add `"headers": { "Authorization": "Bearer $TRAU_SERVE_TOKEN" }`.

## Tool reference

Every tool takes the repo it acts on **by name**. Call `list_repos` first — it reports
the names the rest of the surface expects, each repo's `kind` (`repo` | `folder`),
whether a `Repo:` declaration is mandatory (`worktrees`), its folder `children`, its
`project`, and whether it can be drained at all (`can_drain`). A repo with
`can_drain: false` is observe-only: the reads work, but `enqueue`, `start_queue`,
`pause_queue`, `list_eligible` and `get_epic` are refused on it.

Each tool's own MCP description states its full contract (argument shapes, what is
refused and why), so `tools/list` is the authoritative schema; the tables below are
the map. Thirty-three tools are registered; `reveal_secret` is hidden from
`tools/list` until some listed repo arms it.

### Control

| Tool | What it does |
| --- | --- |
| `list_repos` | The repos this hub serves: name, absolute path, kind, children, worktrees, project, whether the queue can drain. |
| `add_project_repo` | Adds a repo to a hub Project — by a name the hub knows, **or an absolute path it does not know yet**, which registers it on the way in. Seeds the project's tracker keys into the repo; a repo another project holds is moved. Off loopback it needs `SERVE_ALLOW_REGISTER=1` on top of the token. |
| `create_ticket` | Files a ticket in the hub's own issue store, ready-labelled so the loop will pick it up. Pass `labels` explicitly to file something the drain must NOT pick up (the quarantine label for a bug report; a triage label such as `needs-triage` files it into the Inbox instead). `parent` nests it under an epic; `blocked_by` / `blocks` set dependency edges the drain enforces (a cycle is refused). On a **folder repo** pass `repos` (child repo names — written as the `Repo: a, b` first line; never both) — under `WORKTREES=1` a ready ticket declaring neither is refused. |
| `enqueue` | Registers a ticket or epic for execution, at the back of the queue or the front (`front` never displaces a running item). An id that **has children queues as an epic** carrying them. Refused: an epic whose direct children are themselves containers (an epic run covers one level only — the message names the child to queue directly instead), `EPIC_FLOW=0`, and on a folder repo an epic whose `Repo:` pin cannot be placed. Queuing runs nothing on its own. |
| `start_queue` | Arms the drain: pending items run in order — every eligible ticket at once on a worktree repo (folder lanes included), one at a time everywhere else — halting or skipping on a fault per `on_fault` (default `halt`). Refused when the queue is empty or fully settled (`enqueue` first), and when the committed team file states a merge-affecting key (`AUTO_MERGE`, `REVIEW_GATE`, `REQUIRE_CI`) differently from what the repo runs with — the refusal names each key with both values, and `acknowledge_drift` (an array of `{key, team, effective}` repeating that exact set) re-arms for this drain only. |
| `pause_queue` | Stops the drain after the running item exits, leaving every row queued. |
| `resume_run` | Puts a settled row back to pending **from its checkpoint** — no phase re-run, nothing deleted, branch and PR kept. For a failed row, a gate-held one, and now a **quarantined** run whose cause is fixed: the re-entry phase is derived from what the checkpoint durably holds (PR → `pr_open`, commit → `verified`, own branch → `built`), the failure marks are cleared and the tracker is un-quarantined. Refused while a loop is live or the repo is taken over, while the ticket is running or already queued runnable, when the checkpoint is empty or `merged`, and for a quarantined run with nothing to re-enter ("requeue it to start fresh"). Arms nothing: `start_queue` next. |

### Read (always safe)

| Tool | What it does |
| --- | --- |
| `queue_status` | The queue in order with each row's position, kind, status, `held` (per-item Stop), `isolated` (a folder row running in its own lanes), unresolved blockers and epic child counts; `draining` / `draining_since` / `stopping` / `stopping_ids`, `current` and `child_live`, `worktrees` (the repo's effective answer, which is what says whether several rows may run at once), `releasing_epic`, the hold quad `held` / `held_gate` / `held_reason` / `held_since`, and `held_drift` when the gate is `team-drift`. |
| `list_backlog` | The whole board with states, labels, epic links and blockers; filters `state[]`, `label`, `source` (`internal` \| `synced`), `assignee`, `q`, `parent`, paged with `limit` / `offset`; the answer carries `counts` and `ready_label`. |
| `list_eligible` | What the picker would actually run next, in the order it would pick. |
| `get_epic` | An epic's direct sub-issues with preview state — `done`, `epic` for a nested parent, `not-ready` for an open child without the ready label (the loop never picks one), `todo` for a buildable child. An epic whose open children are all `not-ready` builds nothing and parks instead of starting, so call this before queuing one. |
| `list_runs` | Every ticket that has run: settled phase, branch, PR, failure class, cost, and a `url` per run. Board order — earliest phase first — capped by `limit` (100, max 500). |
| `get_run` | One run in depth: verdict, per-phase spend, anomalies, artifacts, event tail (`events`, default 20, max 100). Address it by `repo` + `ticket`, **or by `ref`** — the run page URL (`http://<hub>/runs/<repo>/<ticket>`, its `/live/` form) or `<repo>/<ticket>` (ADR 0056). The answer carries `url`; quote that back to humans. |
| `list_instances` | Loop processes alive on this machine right now: pid, ticket, phase, `session_state`, activity, the provider · model @ effort route, `url`. Unscoped by workspace. |
| `list_steer_notes` | A ticket's steer notes in delivery order — pending, delivered (with the phase that consumed it), or expired. `pending_only` narrows it. |
| `get_config` | A repo's resolved config: each key's effective value, the layer it resolved from (project / user / default), that default, and the catalog description. A secret yields `set: true` with an empty value, never the value itself. `keys` narrows it; an unknown name comes back `known: false` rather than failing the call. Readable on an observe-only repo. |
| `list_worktrees` | The repo's worktrees: ticket, `child` (folder lanes), path, branch, state, the app's port / URL / `serve` mode / standing, the lane database (`db_engine`, `db_name`), and the loop holding each — plus `worktrees_enabled`, so an empty list on a serial repo reads as *none by design* rather than as an idle repo. |
| `get_costs` | Machine-wide spend over a rolling window (`days`, default 30, capped 365): totals against the summed daily budget, per day, per repo, per phase, and the flagged anomalies. Every repo the hub serves, not one — this is the answer to "can we afford this drain". Auggie runs report tokens and credits but no USD. |
| `list_deleted_tickets` | The repo's tombstones — ids a `delete_ticket` purged, newest first. The only surface that explains a healthy-looking tracker pull still dropping a ticket. |

### Steer

| Tool | What it does |
| --- | --- |
| `steer_agent` | Queues a note for a ticket's running agent, injected mid-phase without stopping the run. Asynchronous; may expire undelivered — check `list_steer_notes`. `kind` is `note` (the default — prose) or `keys` — whitespace-separated key names (`enter esc up down tab space y n 1`–`9`) typed raw into a live terminal dialog, which land only in a session already running and expire **30 seconds** after queueing. |

### Destructive — confirm with the user first

| Tool | What it does |
| --- | --- |
| `dequeue` | Removes a queued row for good; the ticket itself stays in the store. |
| `move_queue_item` | Shifts a queued item one slot up or down — changes what runs next. |
| `update_ticket` | Overwrites a hub-filed ticket's fields (`title`, `description`, `labels` as a whole set, `state`, `parent` — `""` unnests — `blocked_by` / `blocks` — omit keeps, `[]` clears — and `repos`); no history to recover the old text. Refused on a tracker-synced ticket. |
| `transition_ticket` | Moves a hub-filed ticket's `state` and labels (`add_labels` / `remove_labels`, optional `comment`) — which is what decides whether the loop runs it. On a `WORKTREES=1` folder repo a ticket cannot become ready without a `Repo:` line. |
| `delete_ticket` | Purges a ticket: board data, comments, attachments, relations, **ticket secrets**, queue rows, the local and remote feature branch. The **run history survives** (`clear_run` first if the checkpoint must go too), and a **tombstone** keeps the identifier out of every later tracker sync until `restore_ticket` lifts it. Deleting an epic takes its children; a mid-run family member is refused. |
| `restore_ticket` | Lifts a tombstone, clears the sync cursor and pulls at once. Board data does not come back; a ticket the tracker no longer returns stays away and the answer says so. (The hub does not flag it destructive; it sits here because it changes what every later sync brings back.) |
| `reset_run` | Throws a run away: drops branch + checkpoint and re-queues the ticket, so the next run starts from nothing. Unmerged work on that branch goes with it. `force` is needed to reset an already-merged ticket (it drops the shipped branch). Refused while a loop is live in the repo or the repo is taken over. |
| `requeue_ticket` | The start-fresh undo: restores the tracker labels and status, clears the checkpoint, closes the attempt PR, drops its branch and worktree, and leaves the queue row `pending`. It hands back the *same ticket text*, so it only helps once the cause is gone. Prefer `resume_run` when the quarantined run still holds a PR, commit or branch worth keeping. Refused while the repo drains or a loop is live; `force` acts on a merged ticket or a branch carrying verified work. |
| `clear_run` | Forgets a ticket's checkpoint, artifacts and phase logs in the hub — no git, no tracker. For tickets finished out-of-band. |
| `retry_release` | Hands an epic parked at `awaiting-merge` back to trau, so the next drain retries the stack merge itself: clears the hand-off marker, puts the row back to pending, re-runs no phase, deletes nothing. Refused when the epic is not parked on a release, when its top PR is already merged or closed, and while a run holds the ticket. |
| `stop_instance` | Sends the live loop process the Ctrl-C-equivalent signal (SIGTERM; CTRL_BREAK on Windows) so it checkpoints and exits; the queue row settles `paused` with class `stopped` at the reached phase. The hub then ends the ticket's lane apps and verifies each port is free; a process that survives inside the worktree marks the *app* row failed and is reported. Only a pid `list_instances` reports. |
| `reveal_secret` | Hands back **one** stored secret in the clear — `scope: config` (a secret config key) or `scope: ticket` (a ticket secret, walking the epic chain) — with a **mandatory `reason`**. Writes a `secret_revealed` forensics event (key, scope, ticket, reason, client — never the value). Only works on a repo with `SECRET_REVEAL=admin`; a non-secret key is refused ("`get_config` already returns its value"). Absent from `tools/list` until some repo is armed. Treat every call as an audited disclosure the user asked for. |
| `restart_hub` | Restarts the hub, dropping every open connection including the caller's. A hub **not started by `trau serve`** has no successor to spawn and refuses. |

## Read-only REST fallback

When the hub is up but no MCP client is configured, the same reads are plain `GET`s
under `{origin}/api/v1` — no setup needed on a loopback hub (add the Bearer header on
an exposed one). A `?workspace=<id>` query scopes `/repos`, `/instances`, `/costs`,
`/notifications`, `/projects`, `/events/stream` and `/search` to one workspace's
projects (ADR 0073); the MCP tools are never scoped.

| Path | MCP equivalent |
| --- | --- |
| `/health`, `/update` | hub liveness and version; pending restart / self-reload, whether an update is installable |
| `/system`, `/providers/usage`, `/providers/accounts` | machine and provider standing, which account each provider is signed in as (no MCP equivalent) |
| `/repos` | `list_repos` — but the REST fields are `name`, `root`, `allowed`, `registered`, `kind`, `child_repos` (a **count**), `freshness`, **not** the MCP payload's `path` / `can_drain` / `children` |
| `/repos/{repo}/queue` | `queue_status` (fields: `draining`, `draining_since`, `stopping`, `stopping_ids`, `worktrees`, `releasing_epic`, `held`/`held_gate`/`held_reason`/`held_since`, `held_drift`, items) |
| `/repos/{repo}/eligible` | `list_eligible` |
| `/repos/{repo}/backlog` | `list_backlog` |
| `/repos/{repo}/epics/{epic}` | `get_epic` |
| `/repos/{repo}/runs` | `list_runs` |
| `/repos/{repo}/runs/{ticket}` | `get_run` — plus GET `/spend`, `/logs` (phase logs), `/log` (the child's console log), `/diff`, `/proofs`, `/artifacts/{kind}`, `/checkpoint`. (`/anomalies` is POST; the bare `/artifacts` is DELETE.) |
| `/repos/{repo}/config` | `get_config` — secrets masked here too |
| `/repos/{repo}/worktrees` | `list_worktrees` |
| `/repos/{repo}/tombstones` | `list_deleted_tickets` |
| `/repos/{repo}/tickets/{id}/secrets` | the ticket's secret **names** only (`name`, `from`, `updated_at`) |
| `/instances` | `list_instances` |
| `/costs`, `/costs/timeseries` | `get_costs` |
| `/notifications` | the bell: paused / faulted / quarantined runs, human holds, hold reminders, parked epics, interview questions (no MCP equivalent) |
| `/workspaces`, `/workspaces/{id}`, `/repos/{repo}/workspaces`, `/projects` | workspace and project structure (no MCP equivalent) |
| `/repos/{repo}/events/stream`, `/repos/{repo}/transcript/stream` | the live event and transcript streams `trau forensics events --follow` and `trau watch` read |
| `/repos/{repo}/publish` | the repo's Publish session, if one is live |
| `/repos/{repo}/dump/estimate` | the size estimate for what `trau dump` would build (the build itself is POST `/dump`) |

One read to know and avoid: `GET /repos/{repo}/tickets/{id}/secrets/resolve` returns
a ticket's resolved secrets **in the clear**, gated only by the hub's bind/token
policy — not by `SECRET_REVEAL`. Do not fetch it unless the user asked for those
values; prefer `reveal_secret`, which is audited.

Write paths worth knowing by name, because there is no MCP tool for some of them:
`POST /repos/{repo}/runs/{ticket}/resume` (`resume_run`),
`POST …/retry-release` (`retry_release`),
`POST …/address-review` (hands an `awaiting-changes` row back into the run order —
409 unless the row is `awaiting-changes`),
`POST …/qa/approve` and `…/qa/reject` (the QA gate — otherwise the run page only),
`POST /repos/{repo}/queue/drift-ack` (the team-drift acknowledgement),
`POST /repos/{repo}/secrets/reveal` (`reveal_secret`).

Two data caveats: a run list's `updated_at` can be a batch stamp (an epic finalize
marks all children with one identical timestamp), and both the REST list and
`trau forensics runs` come back in board order (earliest phase first, then ticket),
never by recency — sort client-side when answering "what settled last". Write operations exist on REST too, but prefer MCP or the CLI for
them: the tool contracts carry the refusal logic and confirmations this skill's
safety rules assume.

## Worked examples

### File a ticket and start the queue

```
list_repos
→ {"repos": [{"name": "acme", "path": "/Users/me/Projects/acme", "kind": "repo",
              "worktrees": true, "can_drain": true, "project": {"id": 3, "name": "Acme"}}]}

create_ticket  repo=acme
               title="Cache the assignee lookup"
               description="The board refetches assignees per row. Resolve once per
                            page and memoize by id. Done when the Backlog view issues
                            one lookup."
→ {"repo": "acme", "id": "ACME-42", ...}

enqueue        repo=acme  id=ACME-42
→ position 1, status pending

start_queue    repo=acme  on_fault=halt
→ draining true
```

`queue_status repo=acme` then reports `current: ACME-42` while it runs, and
`child_live` tells you the run's process is still up. (`child_live` exists only in
the MCP response; the REST queue payload carries `draining` / `stopping` / `held`
and per-item statuses instead.)

If `start_queue` comes back refusing on team drift, it names the keys:

```
start_queue    repo=acme  on_fault=halt
→ refused: .trau/config.team.ini states AUTO_MERGE=0, this repo runs AUTO_MERGE=1

# either fix the config, or — with the user's say-so — acknowledge for this drain:
start_queue    repo=acme  on_fault=halt
               acknowledge_drift=[{"key":"AUTO_MERGE","team":"0","effective":"1"}]
→ draining true
```

### Watch a run and steer it

```
list_instances
→ pid 51233, repo acme, ticket ACME-42, phase build, claude · opus @ high

steer_agent    repo=acme  ticket=ACME-42
               body="Also update docs/cli-web-parity.md if the route changes."
→ note queued, pending

list_steer_notes  repo=acme  ticket=ACME-42
→ delivered at phase build
```

When the run settles, `get_run repo=acme ticket=ACME-42` gives the verdict, the
concrete verify failures, and the spend it took to get there. A human who pastes
`http://127.0.0.1:8728/runs/acme/ACME-42` is pointing at the same run:
`get_run ref="http://127.0.0.1:8728/runs/acme/ACME-42"`.

### Answer a dialog with keys

When the terminal is sitting on a dialog rather than working — a y/n confirm, a
numbered menu, an arrow-key selection — a prose note is the wrong tool: the agent
only reads one at a phase that reads steer notes, and a dialog can stall a commit
or cleanup phase just as easily.

```
list_instances
→ pid 51233, repo acme, ticket ACME-42, phase build

steer_agent    repo=acme  ticket=ACME-42  kind=keys  body="down down enter"
→ note queued, pending
```

The body is whitespace-separated key names — `enter`, `esc`, `up`, `down`, `tab`,
`space`, `y`, `n`, `1`–`9`, no Ctrl sequences — typed raw into the live session. It
lands only in a session that was already running when it was queued, and only
within 30 seconds; after that it expires untyped and never reaches a later phase's
prompt. Queue one only while watching the terminal.

### Recover a halt

The gentlest step that fits, then re-arm — never `reset_run` as a first move:

```
get_run        repo=acme  ticket=ACME-42
→ failure_class paused, phase verified, reason "… — paused, retry from checkpoint"

resume_run     repo=acme  ticket=ACME-42       # carries on from `verified`, re-runs nothing
→ ticket ACME-42, phase verified, status pending

start_queue    repo=acme  on_fault=halt
→ draining true
```

The same two calls handle a **quarantined** run whose cause is now fixed, as long as
the checkpoint still holds a PR, a commit or a branch — `resume_run` re-enters at
the phase that evidence supports and un-quarantines the tracker. `requeue_ticket`
is for when nothing is worth keeping (or `resume_run` says "requeue it to start
fresh"); `retry_release` is for an epic parked `awaiting-merge`. Whichever you use,
it arms nothing: `start_queue` is always the last step.

### File a trau bug without the drain picking it up

`create_ticket` files ready-for-agent by default — a ready ticket would be picked up
by the very drain you're watching. For a bug report meant for a human, set the labels
explicitly:

```
create_ticket  repo=acme
               labels=["needs-human"]
               title="Drain re-picked ACME-42 after a clean merge"
               description="queue_status showed ACME-42 merged at 14:02 …"
→ filed, not enqueued
```

### Hand a run a credential without pasting it into the ticket

Ticket secrets (ADR 0067) reach the agent as environment variables and never appear
in the ticket text, the transcript or trau's prose. There is no MCP write for them —
the CLI is the writer:

```bash
trau secret set ACME-42 STRIPE_TEST_KEY        # bare NAME: value read from stdin, off argv
trau secret list ACME-42                        # names and timestamps, never values
```

A leak guard **faults the run** if a secret value ends up in the diff or a commit.
Reading one back is `reveal_secret scope=ticket` — only on a repo with
`SECRET_REVEAL=admin`, only with a reason, always audited.
