# Trau over the CLI

The commands that only exist here — `doctor`, `watch`, `takeover`, `forensics`,
`dump`, `config …`, `secret …`, `license …`, `update`, `hub remote`, `worktree init`
/ `test-setup`, and the hub lifecycle — plus per-repo inspection. For hub-wide reads
(all repos' queues, run detail with verdict and anomalies), MCP or the REST paths in
`references/mcp.md` are richer, and the recoveries are not CLI-only:
`--requeue` / `--resume` / `--retry-release` have the MCP twins `requeue_ticket` /
`resume_run` / `retry_release`. Run `trau --help` for the authoritative list; this
reference organizes it by what an operator is trying to do.

Trau resolves the target repo from `--repo <path>`, else `TRAU_REPO_ROOT`, else the
git top-level of the cwd, else a hub-registered root. When operating from outside
the target repo, pass `--repo` explicitly rather than relying on the cwd.

One quirk of the help scan: `trau forensics`, `dump`, `config`, `secret`, `license`,
`update` and `steer` print their own usage on `--help`; every other subcommand
(`doctor`, `hub …`, `watch`, `takeover`, `worktree …`, `stop`, `serve`) prints the
top-level usage instead.

## Install, license, update

Distribution is license-gated (ADR 0062). Homebrew, Scoop and winget are **retired**
and their copies are frozen at v2.39.0 — a `trau --version` of 2.39.0 or lower is the
tell, and the fix is to reinstall through the installer, not to wait for a cask bump.

```bash
curl -fsSL https://get.trau.sh/install.sh | TRAU_LICENSE_KEY=<key> sh
                              # macOS / Linux / WSL2: installs to /usr/local/bin (or
                              #   ~/.local/bin), verifies the checksum, stores the key
trau license set <key>        # store the key in the user config layer (no argument
                              #   reads it from stdin so it never lands in `ps`)
trau license status           # which layer supplies TRAU_LICENSE_KEY and whether
                              #   get.trau.sh accepted it; exit 1 when unset/rejected
trau update --check           # running vs latest; exit 1 when an update exists
trau update                   # download, verify sha256, probe the staged binary,
                              #   swap it in place, then ask a running hub to restart
                              #   onto it once idle (`trau hub restart` forces it)
```

Linux `.deb` / `.rpm` and the Windows zip come from
`https://dl.trau.sh/v1/download/<v>/…?license=<key>` — the recipes are in trau's
README; each ends with `trau license set`. The key is a secret config key
(`TRAU_LICENSE_KEY`), lives in the user layer of the hub database, and an exported
env var overrides the stored one. With no key stored, `UPDATE_CHECK` sends nothing
anywhere. `trau update` never calls sudo — a binary it cannot overwrite gets the
install one-liner printed instead. The hub's **Settings → Updates** does the same
install from the browser.

## Run the loop

```bash
trau                  # resume any in-flight ticket, else pick the next ready one
trau <ID>             # run one specific ticket (an epic runs its sub-issues)
trau --once           # process one ticket end-to-end, then stop
trau --no-resume      # skip the resume scan; always pick fresh
trau --max <N>        # cap iterations for this run (0 = unlimited, the default)
trau --provider <p>   # override the provider: claude | codex | kimi | auggie
trau --no-tui         # plain console output (headless / CI)
trau --parent <ID>    # treat <ID> as an epic and process its sub-issues
                      #   (a bare <PREFIX>-<n> argument is equivalent)
trau --worktree <p>   # run in an existing working tree of the repo; a lane is
                      #   reached this way, never by passing it as --repo
trau --no-serve       # don't autostart the hub for this run
trau --skip <keys>    # per-run phase skips: lintfix, cleanup, verify, ci, review, merge
trau --qa-gate | --no-qa-gate   # per-run QA gate override
```

Interactive `trau` with no arguments opens a TUI main menu — and the onboarding
wizard when the repo is unconfigured, which means **no repo root resolved, or an
empty `LINEAR_TEAM` in the resolved config**. It is not keyed on a missing file:
there is no `.trau.ini` to miss (see `references/config.md`). The TUI wizard offers
to import a committed `.trau/config.team.ini` before asking anything, runs a folder
census, and proposes a `.trau/worktree.yaml`; the web project wizard is where "one
Folder repo vs N repos in a project" is an explicit choice, and its steps are reused
to edit an existing project later. If a run dies mid-ticket, just re-run — it
resumes from the next unfinished phase.

Note for agents: starting a loop from your own shell ties it to your process
lifetime. Prefer queueing through the hub (`enqueue` + `start_queue` over MCP, or the
web UI) so runs are hub-managed; reserve direct `trau <ID> --once` for when the user
asks for a supervised one-off in the terminal.

## Inspect — read-only, always safe

```bash
trau doctor                     # preflight — ✓ / ⚠ / ✗ per check; exit 1 when any
                                #   check is ✗ (warnings alone pass). Several dozen
                                #   checks, many conditional on tracker / forge /
                                #   provider: git, commit (a trial commit object),
                                #   gh / bitbucket, provider + provider-account /
                                #   -bypass, model key, repo / tracker / linear labels /
                                #   issue prefix, forge, review trust, config layers /
                                #   shadowing / booleans / retired config files /
                                #   migrated config / team config, worktree file,
                                #   browser verify / isolation / harness, app serving,
                                #   skills / skills lock, plugin manifests /
                                #   plugin-<name>-<tier>, serena*, write: <repo>,
                                #   web hub, license, remote access,
                                #   notification setting / native notifier / push …,
                                #   hub supervision / hub database / transcript database /
                                #   run logs, worktree roots / dirs, legacy queue / run
                                #   data, epic hierarchy / flags / ready labels, queue
                                #   kinds, undeclared tickets, unknown child repos,
                                #   phantom merges, crash reports.
trau doctor --serena-health     # also start Serena's language server for a live check
                                #   (can take a minute)
trau --dry-run                  # the next eligible ticket, without doing anything
trau --list-eligible [--json]   # the repo's ready tickets in pick order
trau --list-epic <ID> [--json]  # an epic's sub-issues and their states
```

A `⚠` is advisory. Two lines an operator should know by name: **team config** is a
`✗` when the committed team file states `AUTO_MERGE`, `REVIEW_GATE` or `REQUIRE_CI`
differently from what the repo runs with (the same drift `start_queue` refuses), and
**worktree roots** warns about a linked git worktree registered as a repo root —
registration itself is what refuses one (a lane is reached with `--worktree`, never
as the root).

`--json` makes each machine-readable. `--verbose` / `--debug` add diagnostics to
stderr only — stdout and `--json` output stay clean, so they're safe in scripts.

```bash
trau --status [--json]          # saved checkpoints with token/cost totals (+ the daily
                                #   budget line when a BUDGET cap is set)
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
trau forensics log    <ID> [--repo <path>] [--limit <n>] [--full] [--follow] [--json]
```

All read-only, safe mid-incident. `events --follow --json` tails the live event
stream as newline-delimited JSON — the backbone of any monitoring loop. `log` prints
the **console log** a hub-spawned run wrote — the one run artifact that lives on disk
(under the trau home's `logs/<repo>/<TICKET>/`, bounded by `RUN_LOG_KEEP` /
`RUN_LOG_MAX_MB`), and the place to look when a child "exited without a drain
report". Two caveats: queries read the hub over HTTP and **autostart one if none is
running** (fine normally; not what you want when "is the hub up?" is itself the
question — curl `/api/v1/health` first), and `forensics runs` comes back in board
order — earliest phase first, then ticket — not recency; sort client-side for "what
settled last".

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
when the run settles expires undelivered. `--repo` targets another repo.

```bash
trau takeover <ID> [--repo <path>]   # resume a PARKED ticket's recorded claude session here
```

Takeover **does not stop anything**: it refuses while any run is active in the repo
("stop it before taking over") and refuses when the hub is down (it needs the hub for
the repo lock). On a parked ticket it checks out the recorded branch (a plain
`git checkout`, which fails if local changes would be overwritten), stamps the
checkpoint (`TAKEOVER`, `ANOMALIES=takeover`) and hands you
the recorded claude session in this terminal — the repo stays locked for as long as
the terminal lives. Hand-back is manual: closing the terminal parks the ticket; it
re-enters the loop only when queued again (*Run next* in the web UI). The hub run
view's **Open in terminal** (macOS) is the stop-then-hand-over path; the CLI is
only the second half. Takeover lands in a claude session regardless of the ticket's
provider.

## Recover

```bash
trau --resume <ID> [--no-run]  # re-enter a settled run from the phase its checkpoint
                               #   supports (PR → pr_open, commit → verified, branch →
                               #   built), un-quarantine the tracker, keep branch and
                               #   PR, then run it once; --no-run stops after the
                               #   repair so the hub can hand it to the queue
trau --requeue <ID>            # start fresh: restore labels + status, clear the
                               #   checkpoint, close the attempt PR, drop its branch
                               #   and worktree, and put the hub queue row back to
                               #   pending — an armed drain WILL re-run it
trau --retry-release <ID>      # clear an epic's awaiting-merge hand-off marker so the
                               #   next drain retries its stack merge; re-runs no phase
trau --reset <ID>              # drop branch + state, re-queue the ticket
                               #   (refuses if already merged; --force overrides)
trau --reset-local <ID>        # drop branch + run dir only; run history and tracker untouched
trau --clear <ID>              # forget the hub checkpoint, artifacts and phase logs
                               #   only — no git, no tracker (alias --forget); for
                               #   tickets finished out-of-band. Autostarts the hub.
trau --force                   # with --reset or --requeue: act even on a ticket already
                               #   merged, or whose branch still carries verified work
```

Prefer the gentlest that fits. `--resume` (= `resume_run`) is the first move for a
paused, gate-held **or quarantined** run whose cause is fixed and whose checkpoint
still holds a PR, commit or branch. `--requeue` (= `requeue_ticket`) is the
start-fresh path: it hands back the *same ticket text*, so it only helps once the
cause of the quarantine is gone, and it refuses with "already shipped" when the
attempt PR merged unless `--force`. Hand-editing labels in the tracker revives
nothing — the checkpoint and attempt PR still mark the ticket spent. All of these
touch git or the tracker to some degree; confirm with the user.

## Read and share configuration

```bash
trau config get <KEY> [--repo <path>]                 # one key's resolved value on stdout
trau config get <KEY> --reveal --reason "<why>"       # a SECRET key, taken from the hub
                                                      #   and audited (SECRET_REVEAL=admin)
trau config export [--out <file>] [--section <name>]  # team-shareable settings → a file
trau config import [<file>] [--dry-run] [--section <name>]
                                                      # apply a shared file to the project layer
trau config import --from-backup [--dry-run]          # recover values the migration set aside
```

`get` reads the same layering the loop does and prints nothing but the value, so a
script can consume it; a key no layer supplies and no default fills prints nothing
and **exits non-zero**. Plain `get` prints local-layer credentials **in the clear** —
the hub database stores them that way and file permissions are the trust boundary —
so never pipe it somewhere it will be logged. `--reveal` is the audited form: it
asks the hub, requires `--reason`, writes a `secret_revealed` forensics event, and
only works on a repo with `SECRET_REVEAL=admin`.

`export` writes only the keys the catalog marks shareable (default
`.trau/config.team.ini`; `--out -` for stdout). Credentials, personal identity,
machine paths and personal taste never travel; the ones the exporter had set are
*named* in the file's checklist without their values. `--section <title|slug>`
writes one Settings card instead — every key of that section not left at default,
machine-specific ones included — to stdout by default. `import` is add-and-update
into the **project layer** — a key in the file replaces the repo's value, a key
absent from it is left alone, and nothing is ever deleted; `--section` applies only
that card's keys and reports the rest as skipped. `--from-backup` puts back settings
the one-time config migration left in the `.trau.ini.migrated` files, add-only.

Once a team file is committed, drift on `AUTO_MERGE`, `REVIEW_GATE` or `REQUIRE_CI`
between it and the effective config makes `trau doctor` fail, makes a starting run
print a one-line warning, and makes `start_queue` refuse until acknowledged.

There is no `trau config set` — writes go through the hub Settings page, the in-TUI
settings editor, `config import`, or `license set` (the one key with its own verb).
There is no `trau setup` either; the onboarding wizard is the first interactive
`trau` run.

## Ticket secrets

```bash
trau secret set <ID> NAME=value [--repo <path>]   # or a bare NAME: value read from stdin
trau secret unset <ID> NAME
trau secret list <ID>                             # NAME / FROM / UPDATED — never a value
trau secret get <ID> NAME --reveal --reason "<why>"
```

A per-ticket, write-only vault in the hub database (ADR 0067): every agent of the
ticket's next run gets each secret as an environment variable (only plugin secrets
and the PHP pin are appended after them); children inherit down the epic chain
(child wins). Needs a running hub and
never starts one. Names are `^[A-Z][A-Z0-9_]*$`; `set` warns when a value is shorter
than the leak guard's minimum. That guard **faults the run** if a value of six or
more characters shows up in the diff or a commit, and redacts it to `***` in
trau-written prose. `get` needs `--reveal`, `--reason` and `SECRET_REVEAL=admin`,
and writes a `secret_revealed` event. `delete_ticket` purges a ticket's secrets with
it.

## Support bundle

```bash
trau dump [--repo <path>] [--ticket <ID>]... [--runs <N>] [--since <30m|RFC3339>]
          [--out <path>] [--yes]
```

The hub assembles the bundle from its own stores (checkpoints, events, transcripts,
artifacts, the kept run logs), the command adds a `doctor` report, and it writes
`trau-dump-<repo>-<timestamp>.zip` in the cwd, printing only that path. With no
scope flags it takes the 10 most recent runs. It autostarts the hub like forensics.
**The bundle is UNREDACTED** — it asks before it builds, and `--yes` skips that
prompt. Read the warning to the user before agreeing on their behalf, and never post
one anywhere public. (This is the manual, opt-in bundle; the automatic opt-out
**crash reports** are a different thing — see `references/config.md`
`CRASH_REPORTS`.)

## Worktree plumbing

```bash
trau worktree init [--repo <path>] [--child <name>] [--force] [--print]
trau worktree test-setup [--repo <path>] [--child <name>]
```

`init` drafts a repo-committed `.trau/worktree.yaml` — copy globs, named setup steps
with timeouts, how the app serves — from what the repo declares (Node, PHP/Herd, Go,
Python, Rust, Ruby stacks are detected), refusing to overwrite without `--force`;
`--print` writes the draft to stdout. `test-setup` is the dry run of everything a
lane needs before a real ticket depends on it: a scratch tree, the lane database, the
setup steps (or `WORKTREE_SETUP_CMD`), the app and its URL — then it settles all of
it. A **folder repo needs `--child <name>`** for either. Run `test-setup` after
changing any of those keys or the file.

## Hub lifecycle

```bash
trau serve                # foreground hub on 127.0.0.1:8728 (--bind, --port)
trau hub start            # background hub; returns once /api/v1/health answers and
                          #   prints the URL plus next steps (open / install as app /
                          #   phone); idempotent — "hub already running (<version>)"
trau hub restart          # restart onto the current on-disk binary (starts one if none)
trau hub restart --force  # stop a hub whose API has wedged, then start fresh
                          #   (refuses while any run is live)
trau stop                 # stop the hub and leave it stopped, releasing its tailnet
                          #   forward; refuses while loops are live, naming each —
                          #   --force parks those runs first
trau hub supervise        # hand the hub to launchd with KeepAlive (macOS; refuses on
                          #   an exposed bind without SERVE_TOKEN)
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
actionable port-busy error pointing at `trau hub restart --force`. After a binary
upgrade, `trau update` already asks the hub to restart onto the new build once idle;
`trau hub restart` is the manual version.

## Where run data actually lives

**Almost nothing a run produces is a file under the repo.** Since ADR 0008 the loop
child writes everything to the hub over HTTP and the hub persists it in its
database: checkpoints, phase logs, the event stream, agent transcripts, and the
artifacts (`handoff`, `rubric`, `verdict`, `buildnotes`, `lessons`, `review-fix`,
and on lane faults `worktree-setup` / `worktree-database`). There is no
`events.jsonl` to grep and no agent transcript on disk to tail. The one on-disk
artifact is the hub-spawned child's **console log**, under the trau home (not the
repo), read with `trau forensics log`.

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
- `trau forensics log <ID>` — the child's console, for crashes before the first event.
- The hub's web **Run detail** page — the same data, rendered, including the
  transcript and the run log panel.
- `trau watch` — the live transcript, read off the hub's transcript API.
