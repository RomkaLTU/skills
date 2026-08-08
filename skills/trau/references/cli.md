# Trau over the CLI

The commands that only exist here — `doctor`, `watch`, `takeover`, `--requeue`,
`forensics`, and the hub lifecycle — plus per-repo inspection. For hub-wide reads
(all repos' queues, run detail with verdict and anomalies), MCP or the REST paths in
`references/mcp.md` are richer. Run `trau --help` for the authoritative list — this
reference organizes it by what an operator is trying to do.

Trau resolves the target repo from `--repo <path>`, else `TRAU_REPO_ROOT`, else the
git top-level of the cwd. When operating from outside the target repo, pass `--repo`
explicitly rather than relying on the cwd.

## Run the loop

```bash
trau                  # resume any in-flight ticket, else pick the next ready one
trau <ID>             # run one specific ticket (an epic runs its sub-issues)
trau --once           # process one ticket end-to-end, then stop
trau --no-resume      # skip the resume scan; always pick fresh
trau --max <N>        # cap iterations for this run
trau --provider <p>   # override the provider: claude | codex | kimi
trau --no-tui         # plain console output (headless / CI)
```

Interactive `trau` with no arguments opens a TUI main menu (and, in a repo with no
`.trau.ini`, the onboarding wizard). If a run dies mid-ticket, just re-run — it
resumes from the next unfinished phase.

Note for agents: starting a loop from your own shell ties it to your process
lifetime. Prefer queueing through the hub (`enqueue` + `start_queue` over MCP, or the
web UI) so runs are hub-managed; reserve direct `trau <ID> --once` for when the user
asks for a supervised one-off in the terminal.

## Inspect — read-only, always safe

```bash
trau doctor                     # preflight: git, gh auth, provider CLI, config,
                                #   tracker labels, write perms — ✓ / ⚠ / ✗ per check,
                                #   non-zero exit if a required check fails
trau --dry-run                  # the next eligible ticket, without doing anything
trau --list-eligible [--json]   # the repo's ready tickets in pick order
trau --list-epic <ID> [--json]  # an epic's sub-issues and their states
```

`--json` makes each machine-readable. `--verbose` / `--debug` add diagnostics to
stderr only — stdout and `--json` output stay clean, so they're safe in scripts.

```bash
trau --status [--json]          # saved checkpoints with token/cost totals
```

`--status` is nearly read-only, with one deliberate side effect: it auto-reconciles
stale in-flight/quarantined checkpoint rows against the tracker (a self-heal, not a
tracker write you chose). That's what you want when answering "where did things
land" — but under a strict look-don't-touch constraint, read the hub's REST
`/repos/{repo}/checkpoints` or `queue_status` instead.

## Forensics — incident queries over run history

```bash
trau forensics runs   [--repo <path>] [--json]
trau forensics events [--repo <path>] [--ticket <ID>] [--since 30m|2h|RFC3339]
                      [--kind <k>] [--grep <pat>] [--follow] [--limit <n>] [--json]
trau forensics spend  <ID> [--repo <path>] [--json]
```

All read-only, safe mid-incident. `events --follow --json` tails the live event
stream as newline-delimited JSON — the backbone of any monitoring loop. Two
caveats: queries read the hub over HTTP and **autostart one if none is running**
(fine normally; not what you want when "is the hub up?" is itself the question —
curl `/api/v1/health` first), and `forensics runs` sorts by ticket id, not recency —
sort client-side for "what settled last".

## Watch, steer, take over

```bash
trau watch                        # tail the newest active agent transcript, legibly
trau watch --id <stem>            # pin to one transcript under .trau/runs/_agent-results
trau watch path/to/file.pty.log   # or an explicit path
```

`watch` is read-only, follows across phase boundaries, and never touches the loop —
safe to start before, during, or after a run. (Under the TUI, the `w` key is the same
thing inline.)

```bash
trau steer <ID> "use the REST client, not the MCP"
trau steer <ID> - <<'EOF'
Skip the migration for now — the schema change lands in a separate ticket.
EOF
```

`steer` queues the note with the running hub (it never starts one — nothing serving
means nothing to steer) and prints the note id. Delivery is asynchronous: mid-phase
at the agent's next injection point, or at the next phase spawn. A note still queued
when the run settles expires undelivered.

```bash
trau takeover <ID> [--repo <path>]   # resume the ticket's recorded agent session here
```

Takeover stops the run, waits for the loop to release the working tree, then hands
you the recorded claude session in this terminal — the repo stays locked for as long
as the terminal lives. Hand-back is manual: closing the terminal parks the ticket; it
re-enters the loop only when queued again. (The hub run view's **Open in terminal**
is the same affordance, macOS only.)

## Recover

```bash
trau --reset <ID>         # drop branch + state, re-queue the ticket
                          #   (refuses if already merged; --force overrides)
trau --reset-local <ID>   # drop branch + run dir only; run history and tracker untouched
trau --clear <ID>         # forget the local checkpoint only — no git, no tracker
                          #   (for tickets finished out-of-band)
trau --requeue <ID>       # undo a quarantine in one step: restore labels + status,
                          #   clear the checkpoint, close the attempt PR, drop its branch
```

`--requeue` is the only correct way to revive a quarantined (`needs-human`) ticket —
hand-editing labels in the tracker does not, because the checkpoint and attempt PR
still mark it spent. All four are destructive to some degree; confirm with the user.

## Hub lifecycle

```bash
trau serve                # foreground hub on 127.0.0.1:8728 (--bind, --port)
trau hub start            # background hub; returns once /api/v1/health answers;
                          #   idempotent — prints "hub already running" if one is up
trau hub restart          # restart onto the current on-disk binary (starts one if none)
trau hub restart --force  # stop a hub whose API has wedged, then start fresh
                          #   (refuses while any run is live)
trau stop                 # stop the hub and leave it stopped; refuses while loops are
                          #   live, naming each — --force parks those runs first
trau hub supervise        # hand the hub to launchd with KeepAlive (macOS)
trau hub unsupervise      # remove that LaunchAgent and stop the hub with it
trau hub preflight        # prove this binary could serve: open + migrate the DBs, exit
```

On a launchd-supervised hub, `trau stop` refuses outright and points at
`trau hub unsupervise`. A port held by something that is not a hub yields an
actionable port-busy error pointing at `trau hub restart --force`.

## Logs and artifacts

Everything lives under `<repo>/.trau/runs/` (override: `RUNS_DIR`); trau gitignores
it in the target repo automatically.

- `.trau/runs/events.jsonl` — the structured event stream for the whole session.
- `.trau/runs/<ID>/` — per-phase logs for one ticket (`build.log`, `handoff.md`,
  `verify*.log`, …) plus the saved checkpoint. For a quarantined ticket this
  directory holds the full trail of what verify rejected — read it before deciding
  anything.
- `.trau/runs/_agent-results/*.pty.log` — live agent transcripts, what `trau watch`
  tails.
