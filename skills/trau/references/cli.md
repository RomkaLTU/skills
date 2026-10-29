# Trau over the CLI

The commands that only exist here — `doctor`, `watch`, `takeover`, `forensics`,
`dump`, `config get/list/describe/export/import`, `license …`, `update`, `tools …`,
`serena trust`, `skill …`, `browser …`, `qa accounts discover/check`,
`proofs write-test`, `connect …`, `collaborators …`, `hosted …`, `ssh recover`,
`hub remote`, `worktree init` / `test-setup`, and the hub lifecycle — plus per-repo
inspection. For hub-wide reads (all repos' queues, run detail with verdict and
anomalies), MCP or the REST paths in `references/mcp.md` are richer, and many CLI
verbs have MCP twins: `--requeue` / `--resume` / `--retry-release` / `--discard` →
`requeue_ticket` / `resume_run` / `retry_release` / `discard_run`; `trau run reverify`
→ `reverify_run`; `trau adr` → `settle_adr_conflict`; `trau checklist waive` →
`waive_checklist_item`; `trau config set` / `unset` → `set_config`; `trau secret …` →
`set_ticket_secret` / `unset_ticket_secret` / `list_ticket_secrets`;
`trau qa accounts list/add/remove` → `qa_accounts_*`; `trau app-urls detect` →
`app_urls_detect`; `trau connections` → `list_connections` / `remove_connection`.
Run `trau --help` for the authoritative list; this reference organizes it by what an
operator is trying to do. (The hub UI is branded **Cobble**; every command, path and
key stays `trau`.)

Trau resolves the target repo from `--repo <path>`, else `TRAU_REPO_ROOT`, else the
git top-level of the cwd, else a hub-registered root. When operating from outside
the target repo, pass `--repo` explicitly rather than relying on the cwd.

One quirk of the help scan: `forensics`, `dump`, `steer`, `secret`, `checklist`,
`run`, `config`, `qa`, `app-urls`, `adr`, `proofs`, `skill`, `tools`, `serena`,
`browser`, `connect`, `connections`, `collaborators`, `hosted`, `demo`, `license` and
`update` print their own usage on `--help`; `doctor`, `hub …`, `watch`, `takeover`,
`worktree …`, `ssh`, `stop` and `serve` print the top-level usage instead.

## Contents

- [Install, license, update](#install-license-update)
- [Agent tools and Serena trust](#agent-tools-and-serena-trust)
- [Run the loop](#run-the-loop)
- [Inspect — read-only, always safe](#inspect--read-only-always-safe)
- [Forensics — incident queries over run history](#forensics--incident-queries-over-run-history)
- [Watch, steer, take over](#watch-steer-take-over)
- [Recover](#recover)
- [Read, write and share configuration](#read-write-and-share-configuration)
- [Ticket secrets and checklist input](#ticket-secrets-and-checklist-input)
- [QA accounts, app URLs and proofs](#qa-accounts-app-urls-and-proofs)
- [Browser harnesses](#browser-harnesses)
- [Operator skill](#operator-skill)
- [Service connections](#service-connections)
- [Hosted hubs and collaborators](#hosted-hubs-and-collaborators)
- [Support bundle and crash reports](#support-bundle-and-crash-reports)
- [Worktree and transport plumbing](#worktree-and-transport-plumbing)
- [Hub lifecycle](#hub-lifecycle)
- [Where run data actually lives](#where-run-data-actually-lives)
- [Maintainer release recovery](#maintainer-release-recovery)

## Install, license, update

Distribution is **open** (ADR 0106, superseding ADR 0062's download gate): the
installer, `trau update` and the hub's update check and install all work with **no
license key**. The license is enforced by the binary's launch gate, not the download.
Homebrew, Scoop and winget are **retired** and frozen at v2.39.0 — a `trau --version`
of 2.39.0 or lower is the tell, and the fix is to reinstall through the installer.

```bash
curl -fsSL https://get.trau.sh/install.sh | sh
                              # macOS / Linux / WSL2: installs to ~/.local/bin without
                              #   sudo, verifies the sha256, adds ~/.local/bin to the
                              #   login shell's profile, installs the operator skill
                              #   (`trau skill offer --yes`) and runs `trau tools install`
curl -fsSL https://get.trau.sh/install.sh | TRAU_LICENSE_KEY=<key> sh
                              # same, and also stores an optional key
irm https://get.trau.sh/install.ps1 | iex
                              # native Windows (or the per-user MSI at
                              #   https://get.trau.sh/install.msi); ends with the hub
                              #   started and supervised
trau update --check           # running vs latest; exit 1 when an update exists
trau update                   # download, verify sha256, probe the staged binary,
                              #   swap it in place, ask a running hub to restart onto
                              #   it once idle (`trau hub restart` forces it), then
                              #   offer the operator skill when interactive
```

Installer opt-outs: `TRAU_INSTALL_NO_MODIFY_PATH=1` (leave the profile alone),
`TRAU_INSTALL_NO_SKILL=1`, `TRAU_INSTALL_NO_TOOLS=1`, and on Windows
`TRAU_INSTALL_NO_SUPERVISE=1`. After a keyless install the next step is `trau serve`
(or `trau hub start --open`), open `http://127.0.0.1:8728`, and **start the 14-day
trial or type a key on the hub's lock screen**. `TRAU_INSTALL_DIR=<abs path>` picks
another destination — the only case the installer may use sudo; run as root it
requires `TRAU_INSTALL_DIR`, stores no key and installs no tools. One exception to "no
key": a release older than the license Worker's `OPEN_DOWNLOAD_FLOOR` var (the first
launch-gated release) still downloads only with an active key — the installer then
stops with "trau <v> needs a license key". That var lives on get.trau.sh, not in any
trau config. Linux `.deb` / `.rpm` come from `https://dl.trau.sh/v1/download/<v>/…`
(recipes in trau's README). `trau update` never calls sudo — a binary it cannot
overwrite gets the install one-liner printed instead. `UPDATE_CHECK` (default on)
checks get.trau.sh once a day with or without a key. The **Updates** section of the
hub's Settings does the same install from the browser.

Two update rules that change what you see: with `AUTO_UPDATE` on (the default, never on
a dev-channel or hosted hub) the hub installs a newer release itself and restarts at the
next ticket boundary — the drain holds with `held: restarting onto vY` and clears by
itself. And eight hours after the hub first sees a newer release it **refuses new agent
work** (`Update required: this hub runs vX, vY is available. …`, ADR 0322) — a direct
`trau` loop refuses too. The fix is `trau update` with the user's approval, not
`UPDATE_CHECK=0`.

```bash
trau license status           # the doctor's license line, then entitlement state / plan /
                              #   expiry; exit 1 when the key is unset or rejected
trau license set [<key>]      # store the key in the user layer; no argument reads stdin,
                              #   so it never lands in `ps`
trau license trial <email>    # get.trau.sh mails a six-digit code …
trau license trial <email> --code <code>   # … which starts the 14-day trial and stores its key
trau license portal           # a Stripe billing-portal URL; expires after five minutes
trau license installs         # recent installations of this key (up to 50, newest first)
trau license release [<install-id>]        # drop one entry from that list; no id = this machine
```

The entitlement states are `trial`, `licensed`, `grace` and `locked`; the hub computes
them offline from a signed token and refreshes it daily. A license runs on **any number
of machines** (ADR 0275): `release` only removes an entry from the recent-installations
list, locks nothing, and the next refresh lists that machine again. Never `release` to
fix a lock — a stored `locked: install_limit` or `install_released` is an older
release's verdict that the next license refresh clears. On a release build an enforced
`locked` state makes `trau` refuse before its first pick (`this trau installation is
locked: … — buy a license at <url>`, exit 1). `license set` / `trial` go through a
running hub's settings API (applied at once), else straight into the hub database; an
exported `TRAU_LICENSE_KEY` overrides both. The key and the trial address belong to the
user — never invent one, never echo a key.

## Agent tools and Serena trust

```bash
trau tools status [--json]    # one row per tool: installed, path, version, configured,
                              #   signed in — read-only
trau tools install [claude] [codex] [gh] [--sign-in] [--json]
                              # install what is missing (no name = all three) into
                              #   ~/.local/bin, then seed Claude's and Codex's config
trau serena trust [--repo <path>]
                              # add the repo root and worktrees root to Serena's
                              #   trusted_project_path_patterns
```

`tools install` (ADR 0302) uses each vendor's own installer and the GitHub CLI's release
archive (checked against its checksums file). It never calls sudo, refuses to run as
root or an elevated Administrator, never installs Node.js, and never updates or removes
a tool — one already installed by any means is only configured (Claude's
first-run/bypass-permissions prompts, a `[profiles.trau]` Codex profile) so a run never
stops on a first-run dialog. `--sign-in` then offers each tool's own sign-in in that
terminal, in the order claude, codex, gh — a person must be there. When
`list_provider_readiness` says `not_installed` or doctor reports `gh` missing, tell the
user to run it on the hub's machine (or click Install on the hub); don't run it for them.

`serena trust` writes only the missing entries of `~/.serena/serena_config.yml` (and
`<root>/**` for a Folder repo) under Serena's file lock, and nothing when the file has no
`trusted_project_path_patterns` key (Serena then trusts everything); a running Serena
picks it up at its next start. **Running it is the accept** (ADR 0301): Serena then runs
each worktree's `.serena/project.yml` `activation_command`, which a build agent can edit.
Doctor's `serena-trust` warning names the command — give it to the user with that
hazard; never run it or edit the file yourself.

## Run the loop

```bash
trau                  # resume any in-flight ticket, else pick the next ready one
trau <ID>             # run one specific ticket (an epic runs its sub-issues)
trau --once           # process one ticket end-to-end, then stop
trau --no-resume      # skip the resume scan; always pick fresh
trau --max <N>        # cap iterations for this run (overrides MAX_ITERATIONS; 0 = unlimited)
trau --provider <p>   # override the provider: claude | codex | kimi | auggie | copilot | deepseek
trau --allowed-providers <a,b>
                      # narrow the provider lock for this run; never widens the licence
                      #   or TRAU_ALLOWED_PROVIDERS
trau --no-tui         # plain console output (headless / CI)
trau --parent <ID>    # treat <ID> as an epic and process its sub-issues
                      #   (a bare <PREFIX>-<n> argument is equivalent)
trau --worktree <p>   # run in an existing working tree of the repo; a lane is
                      #   reached this way, never by passing it as --repo
trau --no-serve       # don't autostart the hub for this run
trau --skip <keys>    # per-run skips, comma-separated: lintfix, cleanup, verify, ci
trau --delivery automerge|stop
                      # per-run override of DELIVERY (`review` / `merge` are no longer
                      #   skip keys — --skip refuses them and names this flag)
trau --complexity-band low|medium|high
                      # pin every band of this run instead of the Complexity score;
                      #   needs MODELS_BY_COMPLEXITY
```

`--skip`, `--delivery`, `--worktree` and `--no-serve` are parsed but not listed in
`trau --help`. `--run-actor` and `--drain-report` are the drainer's flags (a queued
Collaborator row runs as `--run-actor <id>`, ADR 0331) — never pass them by hand.
`--yes` is a no-op kept for compatibility.

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
trau doctor 2>&1                # preflight; the human report goes to STDERR
trau doctor --all               # list each passing check instead of a count line
trau doctor --problems          # verdict, problems and fix commands only
trau doctor --json              # trau.doctor/v1 report on stdout instead
trau doctor --serena-health     # also start Serena's language server for a live check
                                #   (can take a minute)
trau --dry-run                  # the next eligible ticket, without doing anything
trau --list-eligible [--json]   # the repo's ready tickets in pick order
trau --list-epic <ID> [--json]  # an epic's sub-issues and their states
```

Doctor opens with **one verdict line** — `✗ Blocked`, `? Run path unverified`,
`⚠ Ready with warnings` (or `⚠ Ready with unverified optional checks`) or `✓ Ready` —
then lists problems first in each impact group (failures, unverified, warnings),
with passing checks collapsed to one count line (`--all` expands them; `--all` and
`--problems` cannot be combined). Fix commands are on separate lines and collected once
at the end. The three impact headers are `=== blocks runs ===`, `=== weakens QA ===`,
`=== nice to have ===`, each line `✓ / ⚠ / ✗ / ? name: message`. `?` means unverified,
never a pass; only a blocks-runs `?` yields "Run path unverified". Exit is non-zero when
**any** check is `✗`, optional ones included, whatever the flags; `⚠` and `?` alone exit
0. Doctor starts no migration, browser sign-in, key discovery or remote write. Checks are
conditional on tracker / forge / provider; the families: git, git remote, **git
transport** (asks the hub to reach the remote, because only the hub's process speaks for
a run), commit, gh / gh-stack / bitbucket / forge / tls, provider / provider lock /
-account / -bypass / -first-run, copilot mode, codex-model, claude-base-url, model key,
repo / tracker / linear / jira / azure labels, projects and auth, issue prefix, review
trust, config layers / shadowing / booleans / retired files / migrated config / team
config / team lessons, complexity bands, worktree file / roots / dirs, file watcher,
lane database schema, supabase, test baseline, browser verify / isolation / harness /
packages, login gate, qa roster, qa browser sessions, proof storage (attachment upload,
push dry-run), attachment cache, app serving, herd-mcp, skills / skills lock, serena /
serena-trust, lint fix, `write: <repo>`, web hub, license, **license gate** (warns in
`grace`, fails in an enforced `locked`), remote access, notification / push checks,
capsomnia, hub supervision, hub / transcript database, run logs, legacy queue / run
data / registration, epic hierarchy / base / flags / ready labels, queue kinds,
undeclared tickets, child repos / config / registration, delivered state, phantom
merges, sync warning, crash reports.

Two lines an operator should know by name: **team config** is a `✗` when the
committed team file states `DELIVERY` or `REQUIRE_CI` (the merge-affecting keys)
differently from what the repo runs with (the same drift `start_queue` refuses; other
drift is `⚠`), and **worktree roots** warns about a linked git worktree registered as a
repo root — registration itself is what refuses one (a lane is reached with
`--worktree`, never as the root).

`--json` makes `--status`, `--list-eligible` and `--list-epic` machine-readable.
`--verbose` / `--debug` add diagnostics to stderr only — stdout and `--json` output
stay clean, so they're safe in scripts.

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
trau forensics runs   [--repo <path>] [--epic <ID>] [--ticket <IDs>] [--phase <phases>]
                      [--text <s>] [--json]
trau forensics events [--repo <path>] [--ticket <ID>] [--since 30m|2h|RFC3339]
                      [--kind <k>] [--grep <pat>] [--follow] [--limit <n>] [--json]
trau forensics spend  <ID> [--repo <path>] [--json]
trau forensics log    <ID> [--repo <path>] [--limit <n>] [--full] [--follow] [--json]
```

All read-only, safe mid-incident. `runs` takes the `list_runs` filters: `--epic` (the
epic and its children), `--ticket` (one id or a comma list), `--phase` (comma list, or
`terminal` / `active`) and `--text` (case-insensitive over ticket, title, branch,
failure reason, PR status); with `--json` each row carries the run page `url`.
`events --follow --json` tails the live event stream as newline-delimited JSON — the
backbone of any monitoring loop. `log` prints the **console log** a hub-spawned run
wrote — the one run artifact that lives on disk (under the trau home's
`logs/<repo>/<TICKET>/`, bounded by `RUN_LOG_KEEP` / `RUN_LOG_MAX_MB`), and the place to
look when a child "exited without a drain report". Two caveats: queries read the hub
over HTTP and **autostart one if none is running** (fine normally; not what you want
when "is the hub up?" is itself the question — curl `/api/v1/health` first), and
`forensics runs` comes back in board order — earliest phase first, then ticket — not
recency; sort client-side for "what settled last". With an MCP client connected,
`get_run_log`, `query_events` and `get_run_spend` read the same data without the
autostart.

## Watch, steer, take over

```bash
trau watch                  # follow the newest active agent's live feed, legibly
trau watch --raw            # tail the agent's terminal screen instead of the feed
trau watch --id <id>        # pin to one hub transcript id instead of following
trau watch --repo <path>    # target another repo
```

`watch` takes **no path argument** — anything that is not one of those flags (or
`--verbose` / `--debug`) is `watch: unknown arg`. It reads the hub's feed / transcript
API, not a file on disk, so with no hub up it waits forever ("⏳ waiting for agent
output…") rather than failing. It is read-only, follows across phase boundaries, and
never touches the loop — safe to start before, during, or after a run. (Under the TUI,
the `w` key is the same thing inline.)

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
trau takeover <ID> [--repo <path>]   # resume a parked ticket's recorded agent session here
```

Takeover **does not stop anything**: it refuses while any run is active in the repo
("stop it before taking over") or another takeover holds it, refuses when the hub is
down (it needs the hub for the repo lock), and refuses with "no resumable <provider>
session" when the checkpoint names none. It checks out the recorded branch (a plain
`git checkout`, which fails if local changes would be overwritten), stamps the
checkpoint (`TAKEOVER`, `ANOMALIES=takeover`) and reopens the recorded session **in the
provider that recorded it** in this terminal — nothing runs until the person types; the
repo stays locked for as long as that session lives. Hand-back is manual: closing it
leaves the ticket parked at its checkpoint; it re-enters the loop only when queued again
(*Run next* in the web UI), and MCP `advance_run` moves the checkpoint past a phase the
person finished by hand. The hub run view's **Open in terminal** is the stop-then-hand-
over path — it opens a takeover session on the hub's Terminal page (an outside terminal
only on macOS); the CLI is only the second half.

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
                               #   next drain retries its merge; re-runs no phase
trau --reset <ID>              # drop branch + state, re-queue the ticket
                               #   (refuses if already merged; --force overrides)
trau --reset-local <ID>        # drop the ticket's worktree, feature branch (local AND
                               #   pushed) and run dir; run history and tracker untouched
trau --clear <ID>              # forget the hub checkpoint, artifacts and phase logs
                               #   only — no git, no tracker (alias --forget); for
                               #   tickets finished out-of-band. Autostarts the hub.
trau --force                   # with --reset or --requeue: act even on a ticket already
                               #   merged, or whose branch still carries verified work
trau --discard <ID>            # throw the run away — always forced: close the attempt
                               #   PR, keep verified commits under refs/trau/lost/<id>/,
                               #   delete the branch local and remote, reset the tracker
                               #   and quarantine the ticket needs-human
trau run reverify <ID>         # a new conformance pass over the merged base of a shipped
                               #   epic or ticket, through the hub (costs one agent call)
trau --reverify <ID>           # the same pass in this process instead of the hub
```

`--discard` (= `discard_run`, ADR 0352) is the last resort, only with the user, for a
run no other verb clears. Prefer `discard_run` or the **Discard run** button for a live
or queued run: the hub also kills the child, removes the queue row, settles the
worktree and drops checkpoint, artifacts and phase logs (events, transcripts, lessons
and proofs stay), and discards an epic's unmerged children first. A sub-issue of a
queued epic is refused — discard the epic. `run reverify` (= `reverify_run`, ADR 0306)
replaces the conformance result on the run page (earlier ones stay readable); the hub
refuses a ticket that is not shipped or whose pass is already running. Run it only when
the user asks.

```bash
trau adr authorize <ID> [--note "<why>"] [--json]   # supersede exactly the ADRs the
                                                    #   conflict names; resume at verify
trau adr keep <ID> --note "<what to change>" [--json]
                                                    # keep them; resume straight into a
                                                    #   repair that works from the note
```

`trau adr` is the only way out of a run paused with `ADR conflict needs human input:`
(editing the issue does not clear it). Both need a running hub, record the decision
on the checkpoint and comment it on the tracker when it has a writer; an authorization
covers only the ADR paths this conflict named. When the drain is not armed the row
just goes back in the run order. The decision is the user's — ask, never pick.

Prefer the gentlest that fits. `--resume` (= `resume_run`) is the first move for a
paused, gate-held **or quarantined** run whose cause is fixed and whose checkpoint
still holds a PR, commit or branch — note the CLI runs it once right away, while
`resume_run` only puts the row back to pending for the next drain. `--requeue`
(= `requeue_ticket`) is the start-fresh path: it hands back the *same ticket text*, so
it only helps once the cause of the quarantine is gone, and it refuses with "already
shipped" when the attempt PR merged unless `--force`. Hand-editing labels in the
tracker revives nothing — the checkpoint and attempt PR still mark the ticket spent.
The `--status`, `--reset`, `--reset-local`, `--clear`, `--requeue`, `--discard`,
`--resume`, `--retry-release`, `--reverify`, `--dry-run`, `--list-eligible` and
`--list-epic` modes are mutually exclusive. All of the recovery verbs touch git or the
tracker to some degree; confirm with the user.

## Read, write and share configuration

```bash
trau config list [--json]                             # every catalog key, section, default
trau config describe <KEY> [--json]                   # one key's description and metadata
trau config get <KEY> [--repo <path>]                 # one key's resolved value on stdout
trau config get <KEY> --reveal --reason "<why>"       # a SECRET key, taken from the hub
                                                      #   and audited (SECRET_REVEAL=admin)
trau config set <KEY>=<VALUE> [--repo <path>]         # store one key in the PROJECT layer,
                                                      #   through the running hub
trau config unset <KEY> [--repo <path>]               # remove one key from the PROJECT layer
trau config export [--out <file>] [--section <name>]  # team-shareable settings → a file
trau config import [<file>] [--dry-run] [--section <name>]
                                                      # apply a shared file to the project layer
trau config import --from-backup [--dry-run]          # recover values the migration set aside
```

`list` and `describe` read only the catalog built into the binary — offline, no repo,
hub or environment — so they say what a key means and defaults to, never what it is set
to here. `get` reads the same layering the loop does and prints nothing but the value,
so a script can consume it; a key no layer supplies and no default fills prints nothing
and **exits non-zero**, and a key the catalog doesn't know is a usage error. Plain
`get` prints local-layer credentials **in the clear** — the hub database stores them
that way and file permissions are the trust boundary — so never pipe it somewhere it
will be logged. `--reveal` is the audited form: it asks the hub, requires `--reason`,
writes a `secret_revealed` forensics event, and only works on a repo with
`SECRET_REVEAL=admin`.

`set` splits at the first `=` and `unset` takes a bare key; both hand the write to a
**running hub** (they never start one), so they get the Settings page's validation: an
unknown key or a value outside the key's options is refused and nothing is stored. A
secret key prints `(value hidden)`. When a higher layer still supplies the key it says
so — `! <layer> still supplies KEY=…, so the run reads that value instead` — so a
successful `set` is not proof the value is in force; after an `unset` it names the layer
that now supplies the key. The CLI writes only the project layer: the user layer goes
through MCP `set_config` (`layer=user`, `unset=true` to remove) or Settings. The
**hub-wide** keys — every `EXPERIMENTAL_*`, `AI_ASSESSMENT`, `ASSISTANT_REPORTS`,
`HOSTED_REPO_REFRESH`, `ARTIFACT_PUBLIC_SHARE`, `CALIBRATION_AUTO_APPLY` — live in the
user layer only and are refused in the project layer, so no CLI verb sets them.
`license set` remains the one key with its own verb. There is no `trau setup`; the
onboarding wizard is the first interactive `trau` run.

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

Once a team file is committed, drift on `DELIVERY` or `REQUIRE_CI` between it and the
effective config makes `trau doctor` fail, makes a starting run print a one-line
warning, and makes `start_queue` refuse until acknowledged.

## Ticket secrets and checklist input

```bash
trau secret set <ID> NAME=value [--description "<text>"] [--repo <path>]
                                                  # or a bare NAME: value read from stdin
trau secret unset <ID> NAME
trau secret list <ID>                             # NAME / FROM / UPDATED / DESCRIPTION —
                                                  #   never a value
trau secret get <ID> NAME --reveal --reason "<why>"
```

A per-ticket, write-only vault in the hub database (ADR 0067): every agent of the
ticket's next run gets each secret as an environment variable; children inherit down
the epic chain (child wins). Needs a running hub and never starts one. Names are
`^[A-Z][A-Z0-9_]*$`; `set` warns when a value is shorter than the leak guard's
minimum. That guard **faults the run** if a value of six or more characters shows up
in the diff or a commit, and redacts it to `***` in trau-written prose.
`--description` stores a non-secret line beside the name (whose account, what it opens)
that `list` and the agent prompts show — never put a value in it; a `set` without it
keeps the stored one, `--description ""` clears it. Values are sealed with the hub's
ticket-secrets key (`TRAU_TICKET_SECRETS_KEY`, else `<trau home>/keys/ticket-secrets.key`,
ADR 0275): with that key missing or different a `set` fails with 503 while `unset`
still works. `get` needs `--reveal`, `--reason` and `SECRET_REVEAL=admin`, and writes a
`secret_revealed` event. A settled run needs a resume to pick up a new secret.
`delete_ticket` purges a ticket's secrets with it.

```bash
trau checklist waive <ID> <item> --note "<why>" [--repo <path>]
```

Records the user's decision that the run goes on **without** an input an input request
asks for; `<item>` is the item id or its exact title (two items with that title → pass
the id), and `--note` is required. An inherited item is waived on the ancestor that
owns it. A run held at the verify gate with `input_not_supplied` continues past it on
approve once every item it names is waived. Needs a running hub. Waive only when the
user decided so, with their reason as the note.

## QA accounts, app URLs and proofs

```bash
trau qa accounts list [--json]
trau qa accounts add <label> [--username <u>] [--description <t>] [--app-url <id>]
                     [--source manual|agent] [--secret-stdin | --no-secret]
trau qa accounts remove <id>
trau qa accounts discover [--workspace <name>] [--json]    # propose; stores nothing
trau qa accounts check <id>... --page </path> [--workspace <name>] [--yes]
trau app-urls detect [--save <n> | --ask-agent] [--json]
trau proofs write-test [--yes] [--json]
```

The hub owns the QA sign-in roster the browser verifier uses, so every `qa` command
needs a running hub (never starts one) and takes the Settings page's validation:
labels are unique per repo, `--app-url` must be an app URL id of this repo. A secret
**never travels as an argument**: `add` prompts without echo on a terminal, reads
stdin with `--secret-stdin` (the scripted form), or stores none with `--no-secret`;
with no terminal and neither flag it refuses. Nothing prints a secret back. Remove by
the `id` `list` reports. Validation (`unverified` / `passed` / `failed`) is set only by
a sign-in check, and a changed username, secret or app binding resets it.
`discover` reads seeders, factories, role enums, policies and models and proposes only
accounts the code evidences, never printing a password. `check` signs each account in
on a **scratch lane** (never a stored app URL) and opens `--page`; it prints its plan
and asks first — `--yes` only with the user's approval; SSO, 2FA or a captcha leaves
the account `unverified`; exit 1 unless every account passed.

`app-urls detect` asks the hub to collect and probe the app URL candidates browser
verify can drive — `.env` `APP_URL`, running App page sessions, the Herd site, the Vite
port, a Compose web service port — for the repo and each child repo or package
workspace, and prints a numbered list. `--save <n>` stores candidate `n` as an app URL
entry (a workspace that already holds one is refused; a candidate not answering now
can still be saved). `--ask-agent` **starts an agent run** that proposes candidates
from the repo files and merges them in (source `agent`) — the agent saves nothing, so
save its pick with `--save` afterwards. Needs a running hub.

`proofs write-test` asks the hub to push one empty orphan commit to a new random
`refs/heads/trau-proofs-probe/…` ref, read it back and delete it — previewing first
and asking unless `--yes`. It touches no other ref, proof or attachment; a GitHub
attachment destination is reported unverified and nothing is written; exit 1 unless it
passed. `trau doctor`'s proof storage lines are dry runs ("dry-run passed; actual write
unverified") and prove no publication.

## Browser harnesses

```bash
trau browser status [--json]          # selection, both harnesses, the shared browser;
                                      #   reads the trau home only, downloads nothing
trau browser setup [--system]         # download, verify, activate both managed runtimes;
                                      #   each reported on its own
trau browser check [--harness <id>] [--json]
                                      # drive a synthetic loopback form, keep a
                                      #   screenshot, close only what it started
```

Harness ids: `agent-browser` and `browser-harness`; `BROWSER_HARNESSES` is the ordered
selection (first = primary, later = startup fallbacks; a single entry disables
fallback), `BROWSER_BIN` the shared browser. Runtimes live under `<TRAU_HOME>/browser`
and touch no user, shell or repo file. `setup` downloads — run it only when the user
asks; a ready harness stays usable when the other fails. `--system` also installs OS
packages through the host's package manager in that terminal and needs a person at the
machine to authorize it. `check` with no `--harness` drives every harness on the same
fixture for comparison.

## Operator skill

```bash
trau skill show                   # print the SKILL.md this binary embeds (its own version)
trau skill export <dir> [--force] # write it to <dir>/SKILL.md; keeps an existing file
trau skill status                 # the global skill this OS account has, last check verdict
trau skill check                  # compare the installed skill with upstream; read-only
trau skill install [--yes]        # install / update the global skill after accepting
trau skill offer [--yes]          # ask once (what `trau update` runs; --yes is what
                                  #   install.sh / install.ps1 run)
```

Two different copies: `show` / `export` (and a hub's `GET /api/v1/operator-skill` /
`…/download`, `X-Trau-Version` header) give the terse skill **embedded in this binary**;
`install` runs `npx skills add RomkaLTU/skills@trau -g -y` — the published skill — into
the home of the OS account running it, never a project. It never calls sudo or installs
Node: with no `npx` on PATH it writes the embedded copy into `~/.agents/skills/trau` and
`~/.claude/skills/trau` (no update check runs on that copy; the hub refreshes it after
each trau update, and a later `trau skill install` with npx moves it onto skills.sh). A
declined first offer is never asked again; `SKILL_UPDATE_CHECK=0` stops the daily
upstream compare.

## Service connections

```bash
trau connect linear|jira|bitbucket|github [--repo <path>]
                                                     # OAuth sign-in in the user's browser
trau connect github --device                         # GitHub device flow: prints a code for
                                                     #   github.com/login/device
trau connections                                     # id, service, account, sites, expiry,
                                                     #   status — never a token
trau connections remove <id>                         # disconnect and revoke; confirm first
```

All need a running hub (it holds the connections) and never start one. `connect`
opens the consent page — only the user can approve it. Linear and Jira sign in through
get.trau.sh and need the licence key, unless `JIRA_OAUTH_CLIENT_ID` / `_SECRET` name
the operator's own Atlassian app; Bitbucket always uses the operator's own consumer
(`BITBUCKET_OAUTH_CLIENT_ID` / `_SECRET`). GitHub (ADR 0327) signs in through trau's
GitHub App over get.trau.sh, or the operator's own app when `GITHUB_OAUTH_CLIENT_ID` /
`_SECRET` are set; `GITHUB_CONNECTION` picks one of several. `--device` works only with
github, and `connect github` takes the device flow by itself over SSH, with no display,
or against a non-loopback hub; it ends `connected as <login>` or with `denied`,
`expired` or `disabled`. `gh` still runs the GitHub calls. A resolved connection
outranks the API-token keys. When a revoke fails, `remove` still deletes the row and
prints a warning on stderr saying where to revoke the grant by hand — pass it on.

Internal, never run yourself: `trau git-credential get|store|erase` is the credential
helper hub-run git uses for an https `bitbucket.org` remote a connection covers.

## Hosted hubs and collaborators

A **hosted** hub (`SERVE_PUBLIC_URL` set, behind a reverse proxy) answers a forwarded
request only with the operator token or a Collaborator's session. These commands are
for the person who runs that hub; all of them are the user's to run, not yours.

```bash
trau collaborators list [--json]       # id, name, email, role, tracker / AI source,
                                       #   status, sessions; then `seats: <active>/<N>`
                                       #   on stderr — never a token
trau collaborators add <name> <email> [--role business|technical]
                       [--tracker personal|environment] [--ai personal|environment] [--json]
                                       # issue an access token, printed ONCE on stdout
trau collaborators revoke <id>         # revoke the token, end its sessions and pages
```

All need a running hub. Never run `add` yourself — it prints the token once, and the
token goes to the person through the user's own channel, never into a URL, ticket or
log. `--role` defaults to `business` (start and approve Business specifications only);
`technical` also gets Technical specifications and Research, Queue / Runs / Monitoring
reads, queueing, drain start/stop and steering (ADR 0329). `--tracker` / `--ai` say
whether that person's tracker and AI access comes from their own connections
(`personal`, the default) or the hub's environment. Each active Collaborator holds one
licence seat: an add past the count fails with `seats_exhausted`. Confirm before
`revoke`. A role change has no CLI verb (Settings → Collaborators; it ends the
session).

```bash
trau hosted status <record.yaml> [--json]
                                       # the setup table, changing nothing; exit 1 while
                                       #   the hub is not ready
trau hosted setup <record.yaml> [--only <step>] [--licence-key-file <path>]
                  [--ai-key-file <path>] [--json]
                                       # prepare one client's environment from its record
trau hosted deploy <record.yaml>... [--rebuild]
                                       # build this trau checkout's image, deploy it to
                                       #   each client
```

`setup` walks the record's steps, probing each first so a re-run repeats nothing done:
on Fly (`flyctl`, `cloudflared`, `fly ssh`) `fly_app`, `volume`, `tunnel`, `dns`; on a
private host (`platform: private`, ssh only) `host`, `kit`; then `deploy_key`,
`secrets`, `deploy`, `health`, `repos`, `tracker`, `collaborators`, `status`. `--only`
runs one step. It creates cloud resources, prompts for the licence and AI keys unless
the `--…-file` flags supply them, and prints collaborator tokens once — never write a
token or key into a record. `deploy` must run inside a clean trau source checkout
(uncommitted or untracked files refuse it), builds remotely on Fly or locally with
docker / podman for a private host, skips a client already on that commit, and
`--rebuild` forces a new image. Once the hub runs, `GET /api/v1/hosted/status`
(Settings → Hosted setup) shows the same checks. `trau hosted api` is internal — the
setup runs it inside the Machine.

## Support bundle and crash reports

```bash
trau dump [--repo <path>] [--ticket <ID>]... [--runs <N>] [--since <30m|RFC3339>]
          [--out <path>] [--yes]
trau crashreport send-test        # send one test event if CRASH_REPORTS is on, else say why not
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

## Worktree and transport plumbing

```bash
trau worktree init [--repo <path>] [--child <name>] [--force] [--print]
trau worktree test-setup [--repo <path>] [--child <name>] [--compare-schema]
trau ssh recover [--repo <path>] [--child <name>]
```

`init` drafts a repo-committed `.trau/worktree.yaml` — copy globs, named setup steps
with timeouts, how the app serves — from what the repo declares (Node, PHP/Herd,
Laravel, Go, Python, Rust, Ruby are detected), refusing to overwrite without `--force`;
`--print` writes the draft to stdout. `test-setup` is the dry run of everything a
lane needs before a real ticket depends on it: the hub's git transport, a scratch
tree, the lane database, the setup steps (or `WORKTREE_SETUP_CMD`), a Laravel tree's
storage link, the app, and one probe of its URL (final status, and whether a sign-in
wall stands in front) — then it settles all of it. `--compare-schema` adds a check of
the lane database against the checked-out migrations. A **folder repo needs
`--child <name>`**. Run `test-setup` after changing any of those keys or the file.

`ssh recover` is for a failed **git transport** check: it asks the hub which ssh keys
this machine documents, proves them against the remote from the hub's process, and
offers a conditional git include pointing the existing remote at the key that works —
opt-in at every step, never rewriting the remote. It needs a running hub and is not
offered for a remote an OAuth connection or `gh` covers.

(`trau demo start|play|status|progress|control|reset|list|export|record` is a
source-checkout tool for scripted presentations on an isolated demo hub (`:8790`, its
own demo home — the everyday hub is never touched); a license-enforcing build refuses
it. Only `trau demo import <file>` runs on any build, unpacking a `.trau-demo` file
into an idle demo hub. It has no operator use for real runs.)

Internal, never run yourself: `trau terminal-turn <url>` is the hook command a Codex
Terminal preset runs to post its callback to the hub.

## Hub lifecycle

```bash
trau serve                # foreground hub on 127.0.0.1:8728 (--bind, --port,
                          #   --allowed-providers)
trau hub start            # background hub; returns once /api/v1/health answers and
                          #   prints the URL plus next steps (open / install as app /
                          #   phone); idempotent — "hub already running (<version>)"
trau hub start --open     # same, then open it in the default browser (also when one
                          #   is already up; SERVE_OPEN opens it on every start)
trau hub restart          # restart onto the current on-disk binary (starts one if none)
trau hub restart --force  # stop a hub whose API has wedged, then start fresh
                          #   (refuses while any run is live)
trau stop                 # stop the hub and leave it stopped, releasing its tailnet
                          #   forward; refuses while loops are live, naming each —
                          #   --force stops those runs first
trau hub supervise        # hand the hub to launchd (macOS), a systemd user unit
                          #   (Linux) or a per-user logon entry (Windows) so a crashed
                          #   one comes back; refuses an exposed bind without
                          #   SERVE_TOKEN, and refuses while runs are live when it
                          #   must replace a running hub
trau hub unsupervise      # remove that unit and stop the hub with it
trau hub preflight        # prove this binary could serve: refuse if the hub database
                          #   is ahead of it, apply the schema to throwaway copies,
                          #   exit — never touches the operator's databases
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

On a supervised hub, `trau stop` refuses outright and points at
`trau hub unsupervise`. A port held by something that is not a hub yields an
actionable port-busy error pointing at `trau hub restart --force`. After a binary
upgrade, `trau update` already asks the hub to restart onto the new build once idle;
`trau hub restart` is the manual version.

## Where run data actually lives

**Almost nothing a run produces is a file under the repo.** Since ADR 0008 the loop
child writes everything to the hub over HTTP and the hub persists it in its
database: checkpoints, phase logs, the event stream, agent transcripts, lessons, and
the run artifacts (`handoff`, `rubric`, `verdict`, `buildnotes`, `testinstructions`,
`benchmark`, `conformance`). There is no `events.jsonl` to grep and no agent transcript
on disk to tail. The one on-disk artifact is the hub-spawned child's **console log**,
under the trau home (not the repo), read with `trau forensics log`.

A `<repo>/.trau/runs/` directory that still exists is leftover from before that
cutover — it is exactly what `trau doctor`'s *legacy run data* check flags, not a
place to read a failure from.

Read a run through the surfaces that own it instead:

- `get_run` over MCP (or `GET /repos/{repo}/runs/{ticket}`) — verdict with the
  concrete verify failures, failure class, per-phase spend, cost anomalies, which
  artifacts the run produced, and the tail of its events. Bulky artifacts are
  flagged as present rather than inlined; `get_artifact` / `/artifacts/{kind}`
  fetches one.
- `trau forensics events --ticket <ID> --json` — the durable event record, and the
  one thing that outlives a worktree the hub has already removed.
- `trau forensics log <ID>` — the child's console, for crashes before the first event.
- The hub's web **Run detail** page — the same data, rendered, including the
  transcript and the run log panel.
- `trau watch` — the live feed, read off the hub's API.

## Maintainer release recovery

These commands run from the Trau source checkout and publish release state. Use only
when the user asks for that action; they are not target-repo run recovery commands.

- `make hotfix COMMIT=<full-sha> [CHANGELOG="one sentence"]`: publish one merged fix
  on top of the advertised release, without an agent or queue hold. The Publish card
  offers the same Hotfix action; no hub MCP tool starts it. A retry of the same commit
  resumes it. Stopping the command does not undo a pushed tag.
- `make yank VERSION=<bad-version>`: restore the last verified release before the bad
  advertised release and mark that version yanked. A hub already on the bad version
  stays on it until a higher fix is advertised.
