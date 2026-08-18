# Configuration — what an operator needs to know

Trau's own `trau.ini.example` (shipped with the binary and in the repo) documents
every knob exhaustively. This reference covers the layering model and the knobs that
answer operator questions — "why didn't it pick my ticket", "why is the drain
serial", "why did it stop at the PR".

## Layering

Verbatim from `trau --help`, lowest to highest precedence:

```
defaults < user layer < ./trau.ini < project layer < environment < flags
```

1. **built-in defaults**
2. **the user layer** — this machine's baseline (provider flags, machine-trust
   knobs). Not a file: since ADR 0051 it is rows in the hub database
   (`config_values`, scope `user`).
3. **`./trau.ini`** in the cwd — the one config *file* layer left, a local fallback
   when no target repo is given.
4. **the project layer** — this repo's own facts, keyed by absolute repo root. Rows
   in the same hub database (scope `project`), and it always beats the user layer,
   so a machine-wide credential can never shadow a repo's own.
5. **environment variables** — any key below, or its collision-safe `TRAU_<KEY>`
   alias (`TRAU_PROVIDER` beats a generic `PROVIDER` in the shell).
6. **CLI flags** (`--repo`, `--provider`, …)

The user and project layers are edited from the hub's **Settings** page, the in-TUI
settings editor, or `trau config import`; read one back with
`trau config get <KEY> [--repo <path>]`. There is no `trau config set`.

The old home-directory and per-repo `.trau.ini` files are **neither read nor written
any more**. A leftover one is imported once and renamed `.trau.ini.migrated`, and
`trau doctor` reports what happened under *config layers*, *retired config files*,
*migrated config* and *config shadowing*. `trau config import --from-backup` puts a
migrated value back if the import dropped something.

Keys ARE the environment-variable names — `PROVIDER=` and `TRAU_PROVIDER` in the
shell are the same knob. The file format, where a file is still involved, is a flat
INI subset (`KEY=value`, `#` comments).

**Secrets are stored clear-text.** The hub database holds them as typed, and
`trau config get` prints them as typed; the database file's permissions are the
whole trust boundary. There is no safer layer to move a credential into.

## Tracker and eligibility

What decides whether the picker sees a ticket at all:

| Key | Meaning |
| --- | --- |
| `TRACKER_PROVIDER` | `linear` \| `jira` \| `azure` \| `github` \| `internal` (trau's own hub-store issues — the automatic fallback when no external tracker is configured). |
| `LINEAR_TEAM` | Team name / Jira project key / Azure team project / GitHub repo slug. |
| `ISSUE_PREFIX` | Ticket-id prefix (`COD`, `ENG`, …) for parsing, branch inference and sentinels. Empty = derived from the team key, falling back to `COD`. |
| `INTERNAL_ISSUE_PREFIX` | Prefix that internally-filed issues are minted under (`LOOP` → `LOOP-42`). Empty = the repo directory name uppercased, then `ISSUE`, then `TRAU` — always skipping the tracker's own key, so a Jira repo bound to `SAVE24` files `LOOP-1`, not `SAVE24-1`. |
| `READY_LABEL` | Default `ready-for-agent` — what makes a ticket eligible to pick. |
| `QUARANTINE_LABEL` | Default `needs-human` — where failed tickets land; also the label to file human-attention tickets under. |
| `QUEUED_LABEL` | Default `queued` — mirrored onto tickets waiting in the hub queue; the hub heals drift on every sync. Set it **empty per machine** when several people's hubs share one tracker, or the hubs will fight over the label. |
| `SPLIT_LABEL` | Default `needs-split` — the managed label marking a ticket a **human** should split into smaller slices before the loop builds it. Applied by Inbox triage, not by any automatic sizing step. |
| `PROJECT` | Ownership guard: when set, the loop only picks tickets in this tracker project — protects multi-repo trackers from cross-repo picks. Empty = no guard. |

"Why didn't it pick my ticket" is almost always answered here: wrong label, wrong
state, a blocker relation, another repo's `PROJECT`, or triage relabelled it
`needs-split`.

## Loop behavior

| Key | Meaning |
| --- | --- |
| `PROVIDER` | `claude` (default, the battle-tested path) \| `codex` \| `kimi`. |
| `AUTO_MERGE` | `1` (default) = merge on green CI; `0` = stop at the open PR for a human. |
| `MERGE_METHOD` | How green PRs land (e.g. squash). |
| `EPIC_FLOW` | `1` (default) = sub-issues run on an epic branch; parent closes via an epic-to-base PR. |
| `REQUIRE_CI` | `auto` (default) = gate merges on CI when the repo has PR CI; force with `1`/`0`. A push-only repo with no PR CI needs `0` or runs die on a bogus CI timeout. |
| `CI_TIMEOUT` / `CI_POLL` / `EXPECTED_CHECKS` | How long to wait for CI, how often to poll, which checks to insist on. |
| `MAX_REPAIRS` / `MAX_BUGFIXES` | Repair attempts (2 / 2) before verify gives up and quarantines. |
| `REVIEW_GATE` | `0` (default). `1` holds a green PR short of the auto-merge until its reviewers say something — an approval merges it, changes requested run the fix rounds and come back to the gate. No timeout; it polls at `CI_POLL`. `AUTO_MERGE=0` supersedes it. |
| `MAX_REVIEW_ROUNDS` | `2` — rounds spent answering a PR's review feedback (fix or decline each thread, reply, re-request review) before it goes to a human. |
| `QA_GATE` | `0` (default). `1` holds every run after green CI and before the merge, at a durable `awaiting-qa` checkpoint a person releases with **Approve**. The lane is freed while it waits and the worktree and its app stay up. An epic holds once, at its release, never per child. |
| `PICK_ROUNDS` | How many "none of these — regenerate" rounds a run held at the UI pick gate gets (default 2). Past the bound the run parks with the operator's notes as its reason — the status you see is `awaiting-pick`. |
| `COMMIT_TEMPLATE` / `PR_TITLE_TEMPLATE` / `BRANCH_TEMPLATE` | Full-control message and name formats; empty = trau's own. A `BRANCH_TEMPLATE` without `{{.Ticket}}` or `{{.ID}}` refuses the config load, and so does any template naming an unknown placeholder. |
| `PR_BODY_TEMPLATE_FILE` | Path (relative to the PR's repo root) to a Markdown `text/template` for PR bodies. A missing, empty or unrenderable file **fails the run** — there is no fallback to the built-in body. |

## Budgets

Hard spend rails — the loop stops rather than crossing them:

`MAX_TICKET_USD`, `MAX_TICKET_TOKENS`, `MAX_DAILY_USD`, `MAX_DAILY_TOKENS`. All
empty by default. A ticket reaching a per-ticket cap is quarantined with a
cost-overrun note and the loop moves on; a per-day cap stops the run cleanly.

Two things to know before reading a number: the **per-day totals also count the
hub's own sessions** — grill interviews, challengers, publish, atlas, video — because
they bill to the same ledger. And on a worktree repo, where every eligible ticket
can run at once, these caps are the *only* throughput throttle there is.

A run that stopped "for no reason" may simply have hit one; `trau forensics spend
<ID>`, `get_costs` and `trau --status` show the numbers.

## Verify

| Key | Meaning |
| --- | --- |
| `VERIFY_CHECKS` | `1` (default) runs the pluggable check library — repo-defined checks in `<repo>/.trau/checks/*.yaml`, or a built-in set (tests, typecheck, lint, anti-placeholder, anti-duplication). `error` severity blocks the merge. |
| `BROWSER_VERIFY` | `auto` (browser QA only for UI slices) \| `always` \| `never`. |
| `APP_URL` / `APP_URLS` | Where browser verify points; `APP_URLS` maps monorepo workspaces to URLs. |
| `VERIFY_PANEL` / `VERIFY_PANEL_POLICY` | Cross-vendor verify: N isolated verifiers from different providers, merged `unanimous` \| `majority` \| `any-pass`. |
| `VERIFY_EFFORT` | `high` \| `medium` (default) \| `low` — how strictly verify grades a slice. It narrows **both** what the verifier investigates and what can fail the verdict, so a lower level is cheaper and faster, not just more lenient: `high` is full adversarial QA, `medium` the rubric plus regressions in what the slice touched, `low` the rubric contract alone. There is no `off`. Not the same knob as `CLAUDE_VERIFY_EFFORT` / `CODEX_VERIFY_EFFORT`, which set the *provider's* reasoning effort for the phase. |
| `QA_NOTES` | `1` (default) posts the run's QA report as a ticket comment on delivery or give-up. |

## Worktrees and parallelism

| Key | Meaning |
| --- | --- |
| `WORKTREES` | `0` (default) = one checkout, serial drain. `1` = each queued run gets its own worktree, branch, and PR — and **every eligible queued ticket runs at once**, with no lane cap (ADR 0047). A folder repo ignores the key. |
| `WORKTREES_DIR` | Where the trees live: `<WORKTREES_DIR>/<repo-name>/<ticket-id>`; defaults to `~/.trau/worktrees`. It must not sit inside a registered repo. |
| `WORKTREE_SETUP_CMD` | Runs in each fresh tree (e.g. `npm ci`); also where per-lane resource separation (DB, ports, caches) belongs — with no cap on lanes, anything the trees would share is this command's to separate. A non-zero exit parks the run faulted with its output kept as an artifact and the tree left standing as evidence. |
| `APP_SERVE` | `auto` (default) \| `herd` \| `command` \| `off` — how a worktree's app is served. `auto` picks Laravel Herd when the `herd` CLI is on PATH and the repo is one of its sites *and* `APP_START_CMD` is empty; the command when it is set; nothing when neither holds. A Herd-served tree gets a `http(s)://<ticket>.test` site and **no port at all**. |
| `APP_START_CMD` | Serves the app from inside a worktree on a hub-allocated port (`$PORT` / `$TRAU_APP_PORT`), so browser verify tests the branch under test. Governed by `APP_SERVE`; empty leaves the browser gate on `APP_URL` / `APP_URLS`. |
| `WORKTREE_PORT_BASE` | Lowest port a worktree app may be given (default `4300`); each tree takes the lowest free port at or above it. |

The per-repo lane cap that used to sit beside these was removed with ADR 0047. A
config still carrying that key loads with the line **ignored silently** — no
warning, no doctor check — so a stray value is never the reason a drain is narrow.

## The hub (`SERVE_*`)

| Key | Meaning |
| --- | --- |
| `SERVE_BIND` / `SERVE_PORT` | Default `127.0.0.1:8728`. |
| `SERVE_TOKEN` | Required the moment the bind leaves loopback — the hub refuses to start exposed without it; all requests then need `Authorization: Bearer`. |
| `SERVE_ALLOW_REGISTER` | `0` (default): on an exposed hub, (un)registering repos over the API is refused even with the token — a leaked token can't widen where agents run. |
| `SERVE_WORKSPACE` | The **startable** allowlist: the hub may only start loops in these repos. Everything else it discovers stays observe-only (stopping an already-running loop works regardless). **Empty — the default — means the hub starts nothing.** It is not a list of the repos the hub serves. |
| `SERVE_REMOTE` | `off` (default) \| `tailscale` — publish the hub on the tailnet's HTTPS port, bind still loopback, no port opened to the internet. `trau hub remote on\|off` writes this key; every hub start then reconciles the forward against it. |
| `SERVE_AUTOSTART` | `1` (default): starting `trau` brings the hub up first. `--no-serve` disables it for one run. |
| `HUB_SELF_RELOAD` | `0` (default). `1` lets this repo ask the hub to restart onto the binary it builds — the hub runs `HUB_RELOAD_BUILD_CMD` (default `make build`) and restarts onto `HUB_DEV_BINARY` (default `bin/trau`), relative to the repo root. A failed build or an unversionable binary is never adopted. |
| `QUEUE_AUTO_RESUME` / `QUEUE_AUTO_RESUME_TRIES` | `0` / `2`. With auto-resume on, the hub re-attempts an item parked by a **blameless pause** (a provider rate or auth wall, an unreachable hub) once a backoff passes — 2 minutes, then 4 — and gives up after N tries. Never for a fault, an unknown outcome or a deliberate Stop. The plan lives in the hub's memory, so a hub restart forgets it and the item stays parked. |

## Providers and credentials

`CLAUDE_BIN` / `CLAUDE_FLAGS`, `CODEX_BIN` / `CODEX_FLAGS` / `CODEX_PROFILE`,
`KIMI_BIN` / `KIMI_FLAGS` configure the agent CLIs; machine-trust flags belong in
the **user layer**, repo facts in the **project layer**.

Tracker credentials: `LINEAR_API_KEY` (enables fast direct GraphQL alongside MCP),
`JIRA_BASE_URL` / `JIRA_EMAIL` / `JIRA_API_TOKEN`, `AZURE_ORG_URL` / `AZURE_PAT`.
Forge credentials: a **Bitbucket Cloud** remote needs `BITBUCKET_EMAIL` and
`BITBUCKET_API_TOKEN` (a scoped Atlassian API token — app passwords were removed in
July 2026) and is **refused before the run spends anything** without them; a GitHub
remote needs neither and keeps using `gh auth`. Reviewer trust on Bitbucket
additionally needs the account to be a repository **ADMIN**, or every reviewer reads
as untrusted and a PR drawing feedback parks for a human.

All of these live clear-text in the hub database like every other key — there is no
"safer file" to put them in, only the database's own permissions.

## Cost and cadence

| Key | Meaning |
| --- | --- |
| `CLAUDE_PROMPT_CACHE_1H` | `hub` (default) \| `all` \| `off` — ask Claude Code for the 1-hour prompt-cache TTL. `hub` covers the hub's own sessions (grill, challengers, publish, atlas, video); `all` adds every claude pipeline phase; `off` strips an inherited setting. No-op on subscription auth. |
| `CLAUDE_<PHASE>_COMPACT_WINDOW` | Per-phase auto-compact window in tokens (100000–1000000) for claude phases — `BUILD`, `HANDOFF`, `VERIFY`, `REPAIR`, `BUGFIX`, `CLEANUP`, `LINTFIX`, `COMMIT`, `PICK`. Unset (the default) leaves Claude Code's own behaviour. Codex and Kimi ignore them. |
| `TEAM_SYNC` | `0` (default). `1` publishes this machine's lessons on a `refs/trau/team/<writer-id>` ref and folds teammates' back in. Refs only, never the working tree, and blameless — an unreachable remote is recorded for `trau doctor` and never pauses a run. |

## Ticket comments

`DELIVERY_COMMENTS`, `QUARANTINE_COMMENTS` and `RESET_COMMENTS` (all `1` by default)
control the ride-along notes trau leaves on a ticket at delivery, at quarantine and
at reset. Turning one off silences the note only — the status move and the label
swap still happen.
