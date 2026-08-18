# Trau over the CLI

The commands that only exist here — `doctor`, `watch`, `takeover`, `forensics`,
`dump`, `config …`, `hub remote`, `worktree test-setup`, and the hub lifecycle —
plus per-repo inspection. For hub-wide reads (all repos' queues, run detail with
verdict and anomalies), MCP or the REST paths in `references/mcp.md` are richer, and
`--requeue` / `--retry-release` are no longer CLI-only — `requeue_ticket` and
`retry_release` do the same over MCP. Run `trau --help` for the authoritative list;
this reference organizes it by what an operator is trying to do.

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
trau --parent <ID>    # treat <ID> as an epic and process its sub-issues
                      #   (a bare <PREFIX>-<n> argument is equivalent)
trau --worktree <p>   # run in an existing working tree of the repo; a lane is
                      #   reached this way, never by passing it as --repo
trau --no-serve       # don't autostart the hub for this run
```

Interactive `trau` with no arguments opens a TUI main menu — and the onboarding
wizard when the repo is unconfigured, which means **no repo root resolved, or an
empty `LINEAR_TEAM` in the resolved config**. It is not keyed on a missing file:
there is no `.trau.ini` to miss (see `references/config.md`). If a run dies
mid-ticket, just re-run — it resumes from the next unfinished phase.

Note for agents: starting a loop from your own shell ties it to your process
lifetime. Prefer queueing through the hub (`enqueue` + `start_queue` over MCP, or the
web UI) so runs are hub-managed; reserve direct `trau <ID> --once` for when the user
asks for a supervised one-off in the terminal.

## Inspect — read-only, always safe

```bash
trau doctor                     # preflight, ~45 checks — ✓ / ⚠ / ✗ each, non-zero
                                #   exit if a required one fails. Covers git and gh
                                #   auth, the provider CLI, forge and remote, tracker
                                #   labels and project, write perms, config layers /
                                #   config shadowing / config booleans / retired
                                #   config files / migrated config / team config,
                                #   epic hierarchy + epic flags + epic ready labels,
                                #   queue kinds, legacy run data, legacy queue,
                                #   worktree roots and worktree dirs, browser verify
                                #   and browser isolation, child repos, hub
                                #   supervision + hub database, skills and skills
                                #   drift, team sync, remote access.
                                #   A linked git worktree registered as a repo root
                                #   is refused, and the *worktree roots* check names
                                #   every root that would be.
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
trau watch                  # follow the newest active agent transcript, legibly
trau watch --id <id>        # pin to one hub transcript id instead of following
trau watch --repo <path>    # target another repo
```

`watch` takes **no path argument** — anything that is not one of those flags is
`watch: unknown arg`. It reads the hub's transcript API, not a file on disk, so
with no hub up it waits forever rather than failing. It is read-only, follows
across phase boundaries, and never touches the loop — safe to start before, during,
or after a run. (Under the TUI, the `w` key is the same thing inline.)

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
trau --retry-release <ID> # clear an epic's awaiting-merge hand-off marker so the next
                          #   drain retries its stack merge; re-runs no phase
trau --force              # with --reset or --requeue: act even on a ticket already
                          #   merged, or whose branch still carries verified work
```

`--requeue` is the only correct way to revive a quarantined (`needs-human`) ticket —
hand-editing labels in the tracker does not, because the checkpoint and attempt PR
still mark it spent. All of these are destructive to some degree; confirm with the
user. Prefer the gentlest that fits: `resume_run` over MCP carries a merely paused or
gate-held run on from its checkpoint without dropping anything, and there is no CLI
equivalent.

## Read and share configuration

```bash
trau config get <KEY> [--repo <path>]        # one key's resolved value on stdout
trau config export [--out <file>]            # team-shareable settings → a file
trau config import [<file>] [--dry-run]      # apply a shared file to the project layer
trau config import --from-backup [--dry-run] # recover values the migration set aside
```

`get` reads the same layering the loop does and prints nothing but the value, so a
script can consume it; a key no layer supplies and no default fills prints nothing
and **exits non-zero**. It prints credentials **in the clear** — the hub database
stores them that way and file permissions are the trust boundary — so never pipe it
somewhere it will be logged.

`export` writes only the keys the catalog marks shareable (default
`.trau/config.team.ini`; `--out -` for stdout). Credentials, personal identity,
machine paths and personal taste never travel; the ones the exporter had set are
*named* in the file's checklist without their values. `import` is add-and-update
into the **project layer** — a key in the file replaces the repo's value, a key
absent from it is left alone, and nothing is ever deleted. `--from-backup` puts
back settings the one-time config migration left in the `.trau.ini.migrated` files,
add-only: a value stored since the migration is an answer somebody gave and is
kept.

There is no `trau config set` — writes go through the hub Settings page, the in-TUI
settings editor, or `config import`. There is no `trau setup` either; the
onboarding wizard is the first interactive `trau` run.

## Support bundle

```bash
trau dump [--ticket <ID>]... [--runs <N>] [--since <30m|RFC3339>] [--out <path>] [--yes]
```

The hub assembles the bundle from its own stores, the command adds a `doctor`
report, and it writes `trau-dump-<repo>-<timestamp>.zip` in the cwd, printing only
that path. **The bundle is UNREDACTED** — it asks before it builds, and `--yes`
skips that prompt. Read the warning to the user before agreeing on their behalf,
and never post one anywhere public.

## Test the worktree plumbing

```bash
trau worktree test-setup [--repo <path>]
```

A dry run of everything a lane needs before a real ticket depends on it: a scratch
tree, `WORKTREE_SETUP_CMD`, the app and its URL — then it settles all of it. The
right thing to run after changing any of those keys.

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

```bash
trau hub remote on        # publish the hub over the tailnet with Tailscale Serve
trau hub remote on --take #   take over a forward another service still answers on
trau hub remote off       # stop publishing; other forwards are left alone
trau hub remote status    # the tailnet URL, what it forwards to, hub up? (+ a QR code)
```

`hub remote` is the blessed remote path and is *not* an exposed bind: the URL is
`https://<magicdns-name>` on 443, the hub's own bind stays loopback, and no serve
token is involved. `on` / `off` write `SERVE_REMOTE`, so every later hub start
reconciles the forward by itself — a reboot or a changed `SERVE_PORT` comes back
reachable with no manual step. A forward nothing answers on is taken over; one
still carrying traffic is refused unless `--take`.

On a launchd-supervised hub, `trau stop` refuses outright and points at
`trau hub unsupervise`. A port held by something that is not a hub yields an
actionable port-busy error pointing at `trau hub restart --force`.

## Where run data actually lives

**Nothing a run produces is a file under the repo.** Since ADR 0008 the loop child
writes everything to the hub over HTTP and the hub persists it in its database:
checkpoints, phase logs, the event stream, agent transcripts, and the artifacts
(`handoff`, `rubric`, `verdict`, `buildnotes`). There is no `events.jsonl` to grep
and no agent transcript on disk to tail.

A `<repo>/.trau/runs/` directory that still exists is leftover from before that
cutover — it is exactly what `trau doctor`'s *legacy run data* check flags, not a
place to read a failure from.

Read a run through the surfaces that own it instead:

- `get_run` over MCP (or `GET /repos/{repo}/runs/{ticket}`) — verdict with the
  concrete verify failures, failure class, per-phase spend, cost anomalies, which
  artifacts the run produced, and the tail of its events. Bulky artifacts are
  flagged as present rather than inlined; `/artifacts/{kind}` fetches one.
- `trau forensics events --ticket <ID> --json` — the durable event record, and the
  one thing that outlives a worktree the hub has already removed.
- The hub's web **Run detail** page — the same data, rendered, including the
  transcript.
- `trau watch` — the live transcript, read off the hub's transcript API.
