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
| `create_ticket` | Files a ticket in the hub's own issue store, ready-labelled so the loop will pick it up. Pass `labels` explicitly to file something the drain must NOT pick up (e.g. the quarantine label for a bug report). |
| `enqueue` | Registers a ticket or epic for execution, at the back of the queue or the front. |
| `start_queue` | Arms the drain: pending items run in order — up to `WORKTREE_PARALLEL` at once with worktrees, one at a time otherwise — halting or skipping on a fault per `on_fault`. |
| `pause_queue` | Stops the drain after the running item exits, leaving every row queued. |

### Read (always safe)

| Tool | What it does |
| --- | --- |
| `queue_status` | The queue in order, whether the drain is armed, what's running, and the `held` / `held_reason` / `held_since` triple. |
| `list_backlog` | The whole board with states, labels, epic links and blockers, filtered and paged. |
| `list_eligible` | What the picker would actually run next, in the order it would pick. |
| `get_epic` | An epic's direct sub-issues with preview state — what queuing the epic would run. |
| `list_runs` | Every ticket that has run: settled phase, branch, PR, failure class, cost. |
| `get_run` | One run in depth: verdict, per-phase spend, anomalies, artifacts, event tail. |
| `list_instances` | Loop processes alive on this machine right now: pid, ticket, phase. |
| `list_steer_notes` | A ticket's steer notes in delivery order — pending, delivered, or expired. |

### Steer

| Tool | What it does |
| --- | --- |
| `steer_agent` | Queues a note for a ticket's running agent, injected mid-phase without stopping the run. Asynchronous; may expire undelivered — check `list_steer_notes`. |

### Destructive — confirm with the user first

| Tool | What it does |
| --- | --- |
| `dequeue` | Removes a queued row for good; the ticket itself stays in the store. |
| `move_queue_item` | Shifts a queued item one slot up or down — changes what runs next. |
| `update_ticket` | Overwrites a hub-filed ticket's fields; no history to recover the old text. |
| `transition_ticket` | Moves a ticket's state and labels — which is what decides whether the loop runs it. |
| `delete_ticket` | Irreversibly deletes a ticket, its board data, its branch and run directory. |
| `reset_run` | Throws a run away: drops branch + checkpoint and re-queues the ticket. |
| `clear_run` | Forgets a ticket's checkpoint alone — no git, no tracker. For tickets finished out-of-band. |
| `stop_instance` | SIGTERMs a live loop process; the ticket parks unfinished at the reached phase. |
| `restart_hub` | Restarts the hub, dropping every open connection including the caller's. |

## Read-only REST fallback

When the hub is up but no MCP client is configured, the same reads are plain `GET`s
under `{origin}/api/v1` — no setup needed on a loopback hub (add the Bearer header on
an exposed one):

| Path | MCP equivalent |
| --- | --- |
| `/health`, `/update` | hub liveness, version, pending restart/self-reload |
| `/repos` | `list_repos` |
| `/repos/{repo}/queue` | `queue_status` (fields: `draining`, `stopping`, `held`/`held_reason`/`held_since`, items) |
| `/repos/{repo}/eligible` | `list_eligible` |
| `/repos/{repo}/backlog` | `list_backlog` |
| `/repos/{repo}/epics/{epic}` | `get_epic` |
| `/repos/{repo}/runs` | `list_runs` |
| `/repos/{repo}/runs/{ticket}` | `get_run` (plus `/spend`, `/anomalies`, `/logs`, `/diff`, `/artifacts` sub-paths) |
| `/instances` | `list_instances` |
| `/costs` | machine-wide spend totals |

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
