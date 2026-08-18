# Trau over MCP

The hub speaks MCP over one streamable-HTTP endpoint — no stdio server to install,
nothing to run beside the hub:

```
POST {origin}/api/v1/mcp
```

`{origin}` is wherever the hub serves — `http://127.0.0.1:8728` by default. Every tool
calls the same store and drain logic as the web UI and the CLI, so what you see over
MCP and what the Queue view shows can never disagree.

In the hub's web UI, **Settings → External agents (MCP)** renders these same setup
snippets with the endpoint already resolved for however the user reached the hub.

## Auth

The endpoint inherits the hub's exposure policy:

- **Loopback binds are open** — a `127.0.0.1` / `localhost` hub needs no credential.
- **Any other bind requires the serve token** — the hub refuses to start exposed
  without `SERVE_TOKEN`, and every request (MCP included) must carry
  `Authorization: Bearer <token>` or gets a `401`.
- **Cross-site browser requests are refused on every bind, loopback included.** A
  state-changing route answers `403 cross-site request blocked` when the request
  carries `Sec-Fetch-Site: cross-site`, or an `Origin` naming a different host than
  the one it was sent to — so a page the user happens to visit cannot fire a
  no-cors `POST` at their hub. Only browsers set those two headers: an MCP client,
  `curl` or the CLI sends neither and is unaffected.
- **Registering or unregistering a repo needs a second gate.** Off loopback it
  requires `SERVE_ALLOW_REGISTER=1` *on top of* the token, so a leaked token cannot
  widen the set of directories trau runs agents in.

### The blessed remote path is not an exposed bind

`trau hub remote on` publishes the hub over the user's tailnet with Tailscale
Serve: the URL is `https://<magicdns-name>` on port 443, the hub's own bind stays
loopback, and there is **no token** — only devices signed in to the tailnet can
reach it at all. `trau hub remote status` prints the URL and a QR code.

The `https://<host>:8728` + `Authorization: Bearer` snippets below describe the
*other* path — a genuinely exposed bind. Don't mix them up: a tailnet hub reached
over 443 needs no header, and adding `SERVE_TOKEN` to one is defence in depth, not
a requirement.

## Per-session MCP endpoints are not the hub MCP

The hub also serves two short-lived, per-session MCP endpoints that have nothing to
do with operating the loop:

- `/api/v1/grill/{sid}/mcp` — server name `trau-grill`, tools `ask_user`,
  `ask_round`, `finish_session`. This is how a grill interview talks back to the
  person driving it.
- `/api/v1/publish/{id}/mcp` — server name `trau-publish`, the reporting channel of
  a Publish session.

Neither carries any of the tools below. An operator agent that finds one of these
connected in its client must not mistake it for the `trau` hub server — check the
server name and the endpoint path before assuming a tool exists.

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
the names the rest of the surface expects and whether each repo can be drained. Each
tool's own MCP description states its full contract (argument shapes, what is refused
and why), so `tools/list` is the authoritative schema; the tables below are the map.

### Control

| Tool | What it does |
| --- | --- |
| `list_repos` | The repos this hub serves: name, absolute path, whether the queue can drain. |
| `create_ticket` | Files a ticket in the hub's own issue store, ready-labelled so the loop will pick it up. Pass `labels` explicitly to file something the drain must NOT pick up (e.g. the quarantine label for a bug report). `parent` nests the new ticket under an existing epic. |
| `enqueue` | Registers a ticket or epic for execution, at the back of the queue or the front (`front` never displaces a running item). An id that **has children queues as an epic** carrying them; a nested epic — one whose parent is itself an epic — is refused. Queuing runs nothing on its own. |
| `start_queue` | Arms the drain: pending items run in order — every eligible ticket at once on a worktree repo, one at a time everywhere else — halting or skipping on a fault per `on_fault` (default `halt`). Starting an empty or fully settled queue is refused, so `enqueue` first. |
| `pause_queue` | Stops the drain after the running item exits, leaving every row queued. |
| `resume_run` | Puts a settled row back to pending **from its checkpoint**, so the next drain carries on from that phase — no phase re-run, nothing deleted, branch and tracker untouched. For a row the queue marked failed, one held at a gate, or an epic's quarantined sub-issue. Refused while a loop is live, while the ticket is running or already queued runnable, and when the checkpoint phase is empty or terminal. Arms nothing: `start_queue` next. |

### Read (always safe)

| Tool | What it does |
| --- | --- |
| `queue_status` | The queue in order with each row's position, kind, status and unresolved blockers; `draining` / `draining_since` / `stopping`, `current` and `child_live`, `worktrees` (the repo's effective answer, which is what says whether several rows may run at once), `releasing_epic`, and the hold quad `held` / `held_gate` / `held_reason` / `held_since`. |
| `list_backlog` | The whole board with states, labels, epic links and blockers, filtered and paged. |
| `list_eligible` | What the picker would actually run next, in the order it would pick. |
| `get_epic` | An epic's direct sub-issues with preview state — `done`, `epic` for a nested parent, `not-ready` for an open child without the ready label (the loop never picks one), `todo` for a buildable child. An epic whose open children are all `not-ready` builds nothing and parks instead of starting, so call this before queuing one. |
| `list_runs` | Every ticket that has run: settled phase, branch, PR, failure class, cost. |
| `get_run` | One run in depth: verdict, per-phase spend, anomalies, artifacts, event tail. |
| `list_instances` | Loop processes alive on this machine right now: pid, ticket, phase. |
| `list_steer_notes` | A ticket's steer notes in delivery order — pending, delivered (with the phase that consumed it), or expired. `pending_only` narrows it. |
| `get_config` | A repo's resolved config: each key's effective value, the layer it resolved from (project / user / default), that default, and the catalog description. A secret yields `set: true` with an empty value, never the value itself. `keys` narrows it; an unknown name comes back `known: false` rather than failing the call. Readable on an observe-only repo. |
| `list_worktrees` | The repo's worktrees: ticket, path, branch, state, the app's port / URL / standing, and the loop holding each — plus `worktrees_enabled`, so an empty list on a serial repo reads as *none by design* rather than as an idle repo. |
| `get_costs` | Machine-wide spend over a rolling window (`days`, default 30, capped 365): totals against the summed daily budget, per day, per repo, per phase, and the flagged anomalies. Every repo the hub serves, not one — this is the answer to "can we afford this drain". |

### Steer

| Tool | What it does |
| --- | --- |
| `steer_agent` | Queues a note for a ticket's running agent, injected mid-phase without stopping the run. Asynchronous; may expire undelivered — check `list_steer_notes`. `kind` is `note` (the default — prose, with `@` references resolved hub-side) or `keys` — whitespace-separated key names typed raw into a live terminal dialog, which land only in a session already running and expire **30 seconds** after queueing. |

### Destructive — confirm with the user first

| Tool | What it does |
| --- | --- |
| `dequeue` | Removes a queued row for good; the ticket itself stays in the store. |
| `move_queue_item` | Shifts a queued item one slot up or down — changes what runs next. |
| `update_ticket` | Overwrites a hub-filed ticket's fields; no history to recover the old text. |
| `transition_ticket` | Moves a ticket's state and labels — which is what decides whether the loop runs it. |
| `delete_ticket` | Irreversibly deletes a ticket, its board data and its branch. The **run history survives** — checkpoint, phase logs and artifacts stay browsable, so `clear_run` first if the checkpoint must go too. Deleting an epic takes its children; a mid-run family member is refused. |
| `reset_run` | Throws a run away: drops branch + checkpoint and re-queues the ticket, so the next run starts from nothing. Unmerged work on that branch goes with it. `force` is needed to reset an already-merged ticket (it drops the shipped branch). Refused while a loop is live in the repo. |
| `requeue_ticket` | The quarantine undo (= `trau --requeue`): restores the tracker labels and status, clears the checkpoint, closes the attempt PR, drops its branch, and leaves the queue row pending. It hands back the *same ticket text*, so it only helps once the cause of the quarantine is gone. Refused while the repo drains or a loop is live; `force` acts on a merged ticket or a branch carrying verified work. |
| `clear_run` | Forgets a ticket's checkpoint alone — no git, no tracker. For tickets finished out-of-band. |
| `retry_release` | Hands an epic parked at `awaiting-merge` back to trau, so the next drain retries the stack merge itself: clears the hand-off marker, puts the row back to pending, re-runs no phase, deletes nothing. Refused when the epic is not parked on a release, when its top PR is already merged or closed, and while a run holds the ticket. |
| `stop_instance` | Asks a live loop process to stop the way Ctrl-C does, so it checkpoints and exits; the ticket parks unfinished at the reached phase. Only a pid `list_instances` reports. |
| `restart_hub` | Restarts the hub, dropping every open connection including the caller's. A hub **not started by `trau serve`** has no successor to spawn and refuses. |

## Read-only REST fallback

When the hub is up but no MCP client is configured, the same reads are plain `GET`s
under `{origin}/api/v1` — no setup needed on a loopback hub (add the Bearer header on
an exposed one):

| Path | MCP equivalent |
| --- | --- |
| `/health`, `/update` | hub liveness, version, pending restart/self-reload |
| `/system`, `/providers/usage` | machine and provider standing (no MCP equivalent) |
| `/repos` | `list_repos` — but the REST fields are `name`, `root`, `allowed`, `registered`, `kind` (`repo` \| `folder`) and `child_repos`, **not** the MCP payload's `path` / `can_drain` |
| `/repos/{repo}/queue` | `queue_status` (fields: `draining`, `draining_since`, `stopping`, `worktrees`, `releasing_epic`, `held`/`held_gate`/`held_reason`/`held_since`, items) |
| `/repos/{repo}/eligible` | `list_eligible` |
| `/repos/{repo}/backlog` | `list_backlog` |
| `/repos/{repo}/epics/{epic}` | `get_epic` |
| `/repos/{repo}/runs` | `list_runs` |
| `/repos/{repo}/runs/{ticket}` | `get_run` (plus `/spend`, `/anomalies`, `/logs`, `/diff`, `/artifacts` sub-paths) |
| `/repos/{repo}/config` | `get_config` — secrets masked here too |
| `/repos/{repo}/worktrees` | `list_worktrees` |
| `/instances` | `list_instances` |
| `/costs` | `get_costs` |
| `/repos/{repo}/events/stream`, `/repos/{repo}/transcript/stream` | the live event and transcript streams `trau forensics events --follow` and `trau watch` read |
| `/repos/{repo}/publish` | the repo's Publish session, if one is live |
| `/repos/{repo}/dump`, `/repos/{repo}/dump/estimate` | what `trau dump` builds, and its size estimate first |

Two write paths worth knowing by name, because their MCP tools are the gentle
recoveries: `POST /repos/{repo}/runs/{ticket}/resume` (`resume_run`) and
`POST /repos/{repo}/runs/{ticket}/retry-release` (`retry_release`).

There is **no** review or awaiting-changes endpoint: a run parked on PR feedback is
visible as the queue item status `awaiting-changes` plus the run's own failure
class, nowhere else.

Two data caveats: a run list's `updated_at` can be a batch stamp (an epic finalize
marks all children with one identical timestamp), and neither the REST list nor
`trau forensics runs` sorts by recency — sort client-side when answering "what
settled last". Write operations exist on REST too, but prefer MCP or the CLI for
them: the tool contracts carry the refusal logic and confirmations this skill's
safety rules assume.

## Worked examples

### File a ticket and start the queue

```
list_repos
→ {"repos": [{"name": "acme", "path": "/Users/me/Projects/acme", "can_drain": true}]}

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

### Watch a run and steer it

```
list_instances
→ pid 51233, repo acme, ticket ACME-42, phase build

steer_agent    repo=acme  ticket=ACME-42
               body="Also update docs/cli-web-parity.md if the route changes."
→ note queued, pending

list_steer_notes  repo=acme  ticket=ACME-42
→ delivered at phase build
```

When the run settles, `get_run repo=acme ticket=ACME-42` gives the verdict, the
concrete verify failures, and the spend it took to get there.

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

`requeue_ticket` replaces `resume_run` when the run *quarantined* rather than
paused — there is no checkpoint worth carrying on from, and the cause must be gone
first. `retry_release` replaces it when the row is an epic parked
`awaiting-merge`. Whichever you use, it arms nothing: `start_queue` is always the
last step.

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
