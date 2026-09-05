# Configuration — what an operator needs to know

Trau's own `trau.ini.example` (in the repo) and the hub's Settings page document
every knob exhaustively. This reference covers the layering model and the knobs that
answer operator questions — "why didn't it pick my ticket", "why is the drain
serial", "why did it stop at the PR", "why did the drain refuse to arm".

## Layering

Verbatim from `trau --help`, lowest to highest precedence:

```
defaults < user layer < ./trau.ini < project layer < environment < flags
```

1. **built-in defaults**
2. **the user layer** — this machine's baseline (provider flags, machine-trust
   knobs, the license key). Not a file: since ADR 0051 it is rows in the hub
   database, scope `user`.
3. **`./trau.ini`** in the cwd — the one config *file* layer left, a local fallback
   when no target repo is given.
4. **the project layer** — this repo's own facts, keyed by absolute repo root. Rows
   in the same hub database (scope `project`), and it always beats the user layer,
   so a machine-wide credential can never shadow a repo's own.
5. **environment variables** — any key below, or its collision-safe `TRAU_<KEY>`
   alias (`TRAU_PROVIDER` beats a generic `PROVIDER` in the shell).
6. **CLI flags** (`--repo`, `--provider`, …)

The user and project layers are edited from the hub's **Settings** page (every
catalog key is web-editable, `SERVE_TOKEN` included — ADR 0055), the in-TUI
settings editor, `trau config import`, or `trau license set`; read one back with
`trau config get <KEY> [--repo <path>]`. There is no `trau config set`.

Two timing facts matter mid-run. **Phase routes are re-resolved before every agent
call** (ADR 0069): change a phase's model, effort, disallowed tools, output style or
compact window in Settings and the *next agent call of the same run* uses it. The
provider itself stays as settled when the ticket started, and budgets, skills and
`VERIFY_EFFORT` still settle at process start. And a **Models by phase preset**
(ADR 0063) applied from a repo's Settings writes the project layer; from the global
page, the user layer.

The old home-directory and per-repo `.trau.ini` files are **neither read nor written
any more**. A leftover one is imported once and renamed `.trau.ini.migrated`, and
`trau doctor` reports what happened under *config layers*, *retired config files*,
*migrated config* and *config shadowing*. `trau config import --from-backup` puts a
migrated value back if the import dropped something. A plain repo's root
`.trau.ini` is not copied into worktrees either.

Keys ARE the environment-variable names — `PROVIDER=` and `TRAU_PROVIDER` in the
shell are the same knob. The file format, where a file is still involved, is a flat
INI subset (`KEY=value`, `#` comments).

**Secrets are stored clear-text** in the hub database, and plain `trau config get`
prints them as typed; the database file's permissions are the trust boundary. The
*hub* side hands nothing back — `get_config`, the config API and Settings report a
secret as "set" only — unless `SECRET_REVEAL=admin` arms the audited reveal path
(`reveal_secret`, `trau config get --reveal`, `trau secret get --reveal`), each call
of which requires a reason and writes a `secret_revealed` forensics event. Secret
keys are left out of `trau config export` and redacted from logs and tracker prose.

## Repo-committed files

Beside the layers, a few files under the repo change behaviour when present:

| File | Role |
| --- | --- |
| `.trau/config.team.ini` | Written by `trau config export`, applied by `import`. Once committed, drift on `AUTO_MERGE`, `REVIEW_GATE` or `REQUIRE_CI` between it and the effective config fails `trau doctor` (*team config*), makes a run print a warning, makes `start_queue` refuse until `acknowledge_drift` repeats the set, and holds a mid-drain queue under the `team-drift` gate. |
| `.trau/worktree.yaml` | `copy:` replaces `WORKTREE_COPY`; `setup:` (named steps, per-step `timeout`, default 15 m) replaces `WORKTREE_SETUP_CMD`; `app:` (`serve`, `run`) replaces `APP_SERVE` + `APP_START_CMD`. Each section takes over only when present; a file that does not parse **faults the run** rather than falling back. `trau worktree init` drafts it, `trau doctor` *worktree file* validates it. |
| `.trau/plugins/<name>.json` | A plugin manifest; a repo file replaces a same-named built-in wholesale. Invalid files are skipped and reported at loop start and by *plugin manifests*. |
| `.trau/checks/*.yaml` | Repo-defined verify checks (`VERIFY_CHECKS`). |

## Tracker and eligibility

What decides whether the picker sees a ticket at all:

| Key | Meaning |
| --- | --- |
| `TRACKER_PROVIDER` | `linear` \| `jira` \| `azure` \| `github` \| `internal` (trau's own hub-store issues — the automatic fallback when no external tracker is configured). |
| `LINEAR_TEAM` | Team name / Jira project key / Azure team project / GitHub repo slug. Empty = the onboarding wizard on the next interactive run. |
| `ISSUE_PREFIX` | Ticket-id prefix (`COD`, `ENG`, …) for parsing, branch inference and sentinels. Empty = derived from the team key, falling back to `COD`; Azure leaves it empty (work items go by number). `trau doctor` *issue prefix* flags one that contradicts the tracker key. |
| `INTERNAL_ISSUE_PREFIX` | Prefix that internally-filed issues are minted under (`LOOP` → `LOOP-42`). Empty = the repo directory name uppercased, then `ISSUE`, then `TRAU` — always skipping the tracker's own key. An internal issue carved from a tracker ticket carries an `origin`, and delivery names the *origin* key on branch, commit and PR — so a forge search for `LOOP-42` finds `SAVE24-761` instead. |
| `READY_LABEL` | Default `ready-for-agent` — what makes a ticket eligible to pick. |
| `QUARANTINE_LABEL` | Default `needs-human` — where failed tickets land; also the label to file human-attention tickets under. |
| `QUEUED_LABEL` | Default `queued` — mirrored onto tickets waiting in the hub queue; the hub heals drift on every sync. Empty = no writes (worth doing per machine when several people's hubs share one tracker). |
| `SPLIT_LABEL` | Default `needs-split` — the managed label marking a ticket a **human** should split before the loop builds it. A triage label (`needs-triage`, `needs-info`, this one) files a ticket into the Inbox rather than the queue, and **queuing, running or "make ready" strips it** — a triage label put back on a queued ticket is removed on the next sync tick. |
| `PROJECT` | Ownership guard: when set, the loop only picks tickets in this tracker project — protects multi-repo trackers from cross-repo picks. Empty = no guard. |
| `EPIC_ADOPT_PARENT` | `queued` (default) \| `always` \| `never` — when a ticket queued on its own builds on its tracker parent's epic branch instead of the base. |

"Why didn't it pick my ticket" is almost always answered here: wrong label, wrong
state, a blocker relation (`blocked_by` edges are enforced), another repo's
`PROJECT`, triage relabelled it, or — on a `WORKTREES=1` folder repo — no `Repo:`
line (see Worktrees). A ticket that vanished from every pull may be tombstoned:
`list_deleted_tickets`.

## Loop behavior

| Key | Meaning |
| --- | --- |
| `PROVIDER` | `claude` (default, the battle-tested path) \| `codex` \| `kimi` \| `auggie` (ADR 0061). Fixed per ticket once a run starts. |
| `AUTO_MERGE` | `1` (default) = merge on green CI; `0` = stop at the open PR for a human (`awaiting-merge`). Merge-affecting: team drift on it blocks the drain. |
| `MERGE_METHOD` | How green PRs land (e.g. squash). `DETERMINISTIC_COMMIT=1` (default) writes a templated Conventional Commit on squash repos. |
| `EPIC_FLOW` | `1` (default) = sub-issues run on an epic branch; parent closes via an epic-to-base PR. `0` refuses `enqueue` of an epic. |
| `EPIC_STACKED_PRS` | `0` (default). `1` = experimental native GitHub stack instead of an epic branch; upper layers defer CI to the stack merge. |
| `REQUIRE_CI` | `auto` (default) = gate merges on CI when the repo has PR CI; a repo with no pull-request workflow waits one `CI_TIMEOUT` and then merges with a warning. `1` insists on checks (absent ones time the run out — set `0` on a push-only repo instead). Merge-affecting. |
| `CI_TIMEOUT` / `CI_POLL` / `EXPECTED_CHECKS` | How long to wait for CI, how often to poll, which checks to insist on. |
| `MAX_REPAIRS` / `MAX_BUGFIXES` | Repair attempts default `2`. **Bugfix attempts default to unlimited** (empty or `0`): a default-config run keeps bugfixing until verify passes or a budget cap stops it, and only an explicit `N` makes verify give up and quarantine. |
| `MAX_ITERATIONS` | Tickets per run; default unlimited (`--max 0`). An epic child loop that hits a cap with open children left reports `capped` and re-queues — not a quarantine. |
| `REVIEW_GATE` | `0` (default). `1` holds a green PR short of the auto-merge until its reviewers say something — an approval merges it, changes requested run the fix rounds and come back to the gate. Applies to an epic's release PR too. No timeout; it polls at `CI_POLL`. `AUTO_MERGE=0` supersedes it. Merge-affecting. |
| `MAX_REVIEW_ROUNDS` | `10` — rounds spent answering a PR's review feedback (fix or decline each thread, reply, re-request review). Exhausted on a **ticket** PR, the run quarantines the disagreement; an epic PR parks `awaiting-changes` instead. |
| `REVIEW_RESOLVE` | `reviewer` (default) \| `trau` — who closes a thread trau fixed: reply and leave it open for the reviewer, or resolve it. Declined threads stay open either way. |
| `TRUSTED_REVIEWERS` | Comma-separated forge identities (GitHub login; Bitbucket `account_id` or `{uuid}`) whose feedback trau acts on regardless of forge permissions — rung 1 of the trust ladder (ADR 0064). Feedback from an author no rung can vouch for **parks** the row `awaiting-changes` until someone is added here or decides on the PR. |
| `QA_GATE` | `0` (default). `1` holds every run after green CI and before the merge, at a durable `awaiting-qa` checkpoint a person releases with **Approve** (or sends back with **Reject**, two fix rounds max). The lane is freed while it waits and the worktree and its app stay up. An epic holds once, at its release. A queued item's own Hold-for-QA choice overrides this in both directions. |
| `COMMIT_TEMPLATE` / `PR_TITLE_TEMPLATE` / `BRANCH_TEMPLATE` | Full-control message and name formats; empty = trau's own (`feature/{{.Ticket}}-{{.Slug}}`). A `BRANCH_TEMPLATE` without `{{.Ticket}}` or `{{.ID}}` refuses the config load, and so does any template naming an unknown placeholder. |
| `PR_BODY_TEMPLATE_FILE` | Path (relative to the PR's repo root) to a Markdown `text/template` for PR bodies. A missing, empty or unrenderable file **fails the run** — there is no fallback to the built-in body. |
| `CLAUDE_DISALLOWED_TOOLS` | `Agent,Workflow,Bash(git push:*),Bash(gh pr create:*)` — delivery commands blocked in every claude phase (the loop delivers, not the agent). Per-phase `CLAUDE_<PHASE>_DISALLOWED_TOOLS`. Codex/Kimi/Auggie have no deny list; the prohibition is prompt-only there. |

The pick gate and `PICK_ROUNDS` no longer exist (ADR 0059).

## Budgets

Hard spend rails — the loop stops rather than crossing them:

`MAX_TICKET_USD`, `MAX_TICKET_TOKENS`, `MAX_DAILY_USD`, `MAX_DAILY_TOKENS`. All
empty by default. A ticket reaching a per-ticket cap is quarantined with a
cost-overrun note and the loop moves on; a per-day cap stops the run cleanly.

Three things to know before reading a number: the **per-day totals also count the
hub's own sessions** — interviews, challengers, publish, atlas, video — because they
bill to the same ledger. On a worktree repo, where every eligible ticket can run at
once, these caps are the *only* throughput throttle. And **the USD caps never fire on
auggie** (it reports tokens and credits, no `cost_usd`; kimi has no price either) —
set the token caps there.

With `MAX_BUGFIXES` unlimited by default, the budget caps are also what bounds a run
that keeps failing verify. A run that stopped "for no reason" may simply have hit
one; `trau forensics spend <ID>`, `get_costs` and `trau --status` show the numbers.

## Verify

| Key | Meaning |
| --- | --- |
| `VERIFY_CHECKS` | `1` (default) runs the pluggable check library — repo-defined checks in `<repo>/.trau/checks/*.yaml`, or a built-in set (tests, typecheck, lint, anti-placeholder, anti-duplication). `error` severity blocks the merge. |
| `BROWSER_VERIFY` | `auto` (browser QA only for UI slices) \| `always` \| `never`. |
| `BROWSER_ISOLATION` | `managed` (default): build always gets a dedicated headless browser, verify / repair / bugfix when the slice has a UI surface, and every other phase has the shared-browser env (`BU_CDP_*`) stripped so no agent drives the user's browser. `attach` is the old shared-browser behaviour. Why no window opens and why two lanes never share tabs. |
| `APP_URL` / `APP_URLS` | Where browser verify points; `APP_URLS` maps monorepo package workspaces to URLs. |
| `VERIFY_PANEL` / `VERIFY_PANEL_POLICY` | Cross-vendor verify: N isolated verifiers from different providers, merged `unanimous` \| `majority` \| `any-pass`. |
| `VERIFY_EFFORT` | `high` \| `medium` (default) \| `low` — how strictly verify grades a slice. It narrows **both** what the verifier investigates and what can fail the verdict, so a lower level is cheaper and faster, not just more lenient: `high` is full adversarial QA, `medium` the rubric plus regressions in what the slice touched, `low` the rubric contract alone. There is no `off`. Not the same knob as `CLAUDE_VERIFY_EFFORT` / `CODEX_VERIFY_EFFORT`, which set the *provider's* reasoning effort for the phase. |
| `TEST_EFFORT` | `low` (default) \| `off` \| `medium` \| `high` — how much test work build is asked for (ADR 0041). |
| `VERIFY_PROOFS` / `PROOF_RETENTION_DAYS` | Screenshots and traces harvested to the hub (14-day retention). On GitHub with `gh` ≥ 2.99 they travel as PR attachments (`gh pr create --attach`, ADR 0073) and are never pruned; a rejected upload retries the PR once without proofs. |
| `QA_NOTES` | `1` (default) posts the run's QA report as a ticket comment on delivery or give-up. |
| `SERENA` / `SERENA_BACKEND` | `auto` (default) \| `required` \| `off` — Serena MCP readiness pre-flight before build (ADR 0057). `required` fails `trau doctor` and pauses a run when it is missing; a build that cannot reach it pauses `tool_unavailable` with the fix in the reason. Backend `auto` \| `LSP` \| `JetBrains`. The pre-flight runs for every provider; on auggie/kimi the registration check is marked *skipped*, never failed. |

## Worktrees and parallelism

| Key | Meaning |
| --- | --- |
| `WORKTREES` | `0` (default) = one checkout, serial drain. `1` = each queued run gets its own worktree, branch, and PR — and **every eligible queued ticket runs at once**, with no lane cap (ADR 0047). On a **folder repo** it means: a ticket whose description opens with `Repo: <child>[, <child>…]` runs in a lane holding one linked worktree per declared child, isolated lanes are unlimited too, and a ready ticket with **no** `Repo:` line is refused before any agent call. |
| `WORKTREES_DIR` | Where the trees live: `<WORKTREES_DIR>/<repo-name>/<ticket-id>` (folder lanes add `/<child>`); defaults to `<TRAU_HOME>/worktrees` (`TRAU_HOME` itself defaults to `~/.trau`). It must not sit inside a registered repo. |
| `WORKTREE_COPY` | `.env,.env.*` — gitignored globs copied into a fresh tree (on top of the unconditional set: `.trau/`, `.gitconfig.repo`, untracked `.agents/`, `.serena/` project + memories, the skills mirror). Replaced by `worktree.yaml` `copy:` when present. |
| `WORKTREE_SETUP_CMD` | Runs in each fresh tree (e.g. `npm ci`) under the host shell. Replaced by `worktree.yaml` `setup:` when present. Caches and search indexes the trees would share are still this command's to separate; **ports and the database are not** — the hub allocates ports and copies the database before it runs. A non-zero exit parks the run faulted with its output kept as a `worktree-setup` artifact and the tree left standing as evidence. Folder lanes resolve it per child. |
| `WORKTREE_DB` / `WORKTREE_DB_URL` | `auto` (default): every lane gets **its own copy of the checkout's dev database** (MySQL/MariaDB/PostgreSQL/SQLite, `docker exec` fallback), named `<source>_<ticket>[_<child>]`, dropped on settle, with the tree's `.env` repointed and `TRAU_DB_*` exported to setup/start commands (ADR 0070). `on` faults instead of sharing when no source is found; `off` copies nothing. A failed copy parks the run faulted with a `worktree-database` artifact. `WORKTREE_DB_URL` is the admin connection URL — a secret. |
| `APP_SERVE` | `auto` (default) \| `herd` \| `command` \| `off` — how a tree's app is served. `auto` picks Laravel Herd when the `herd` CLI is on PATH and the repo is one of its sites *and* `APP_START_CMD` is empty; the command when it is set; nothing when neither holds. A Herd-served tree gets a `http(s)://<ticket>.test` site and **no port at all**. With `WORKTREES=0` the same modes decide the *checkout's own* server: `command` probes the configured app URL, adopts a dev server that already answers, and starts the command only when nothing does; trau stops only servers it started. Replaced by `worktree.yaml` `app:` when present. |
| `APP_START_CMD` | Serves the app from inside a worktree on a hub-allocated port (`$PORT` / `$TRAU_APP_PORT`), so browser verify tests the branch under test. Governed by `APP_SERVE`; empty leaves the browser gate on `APP_URL` / `APP_URLS`. Readiness wait 60 s; a command that never listens is marked failed and the run continues on the advisory no-URL path. |
| `WORKTREE_PORT_BASE` | Lowest port a worktree app may be given (default `4300`); each tree takes the lowest free port at or above it, within a 200-port window. Folder lanes reserve one port per serving child up front. |

The per-repo lane cap that used to sit beside these was removed with ADR 0047.

## The hub (`SERVE_*`)

| Key | Meaning |
| --- | --- |
| `SERVE_BIND` / `SERVE_PORT` | Default `127.0.0.1:8728`. |
| `SERVE_TOKEN` | Required the moment the bind leaves loopback — the hub refuses to start exposed without it; all requests then need `Authorization: Bearer`. Editable from Settings; read at serve start. |
| `SERVE_ALLOW_REGISTER` | `0` (default): on an exposed hub, (un)registering repos, `add_project_repo`, project CRUD, filesystem browse/discover and other widen-the-footprint routes are refused even with the token — a leaked token can't widen where agents run. |
| `SERVE_WORKSPACE` | An extra **startable** allowlist. The hub may start (and stop) loops in the repos **Registered** with it plus whatever this key lists; a repo it merely discovered stays observe-only for both start and stop (`403 repo is observe-only`). Empty — the default — means Registered repos only. It is not a list of the repos the hub serves, and it has nothing to do with hub-UI **Workspaces** (ADR 0073 — a per-browser grouping of Projects with no config key) or `APP_URLS`' *package workspaces*. |
| `SERVE_REMOTE` | `off` (default) \| `tailscale` — publish the hub on the tailnet's HTTPS port, bind still loopback, no port opened to the internet. `trau hub remote on\|off` writes this key; every hub start then reconciles the forward against it. |
| `SERVE_AUTOSTART` | `1` (default): the first interactive `trau` session brings the hub up first. `--no-serve` disables it for one run. |
| `SERVE_OPEN` | `1` (default): a fresh hub spawn (and `trau hub start`) opens the browser. |
| `SECRET_REVEAL` | `off` (default) \| `admin` — arms the audited one-secret-per-call reveal path (`reveal_secret`, `--reveal`). Until a repo sets it, the tool is absent from the hub's `tools/list`. |
| `HUB_SELF_RELOAD` | `0` (default). `1` lets **the trau source checkout** ask the hub to restart onto the binary it builds — `HUB_RELOAD_BUILD_CMD` (default `make build`), `HUB_DEV_BINARY` (default `bin/trau`), `HUB_RELOAD_PULL` (fast-forward first). Any other repo is refused and never sees these keys. |
| `QUEUE_AUTO_RESUME` / `QUEUE_AUTO_RESUME_TRIES` | `0` / `2`. With auto-resume on, the hub re-attempts an item whose run **paused** (any pause reason — a provider wall, an unreachable hub, a dialog) once a backoff passes — 2 minutes × attempt — and gives up after N tries. Never a fault, a stop or a `held` row. The plan lives in the hub's memory, so a hub restart forgets it and the item stays parked. A crashed epic release gets two tries regardless. |
| `UPDATE_CHECK` / `TRAU_LICENSE_KEY` | `1` — ask `get.trau.sh` for newer releases; **needs the license key**, otherwise no request leaves the machine. The key (a secret) is what `install.sh` and `trau license set` store; `trau update` and Settings → Updates install with it (ADR 0062). |
| `CRASH_REPORTS` | `1` (default): a panic or pipeline fault sends one crash event to trau's Sentry (ADR 0057). `0` or `DO_NOT_TRACK=1` disables; `trau doctor` *crash reports* states which. Unrelated to the manual, unredacted `trau dump`. |
| `NOTIFY` / `HOLD_REMINDER_HOURS` | `0` / `24`. `NOTIFY=1` fires a native desktop notification for every bell item — paused / faulted / quarantined runs, PRs awaiting merge or QA, changes requested, hold reminders, epic parked / unparked, interview questions, a finished publish. Rows sitting on a human are re-notified every `HOLD_REMINDER_HOURS` (0 = once). |
| `PLUGINS` | Empty (default). Comma-separated plugin names (built-in: `uizze`); a plugin's skills, MCP servers and prompt line attach to a run only when the ticket or its parent epic carries one of the plugin's activating labels (`ui`, `ux`, `design`, `frontend` for `uizze`), decided once at build (ADR 0072). A plugin whose secret (e.g. `UIZZE_AGENT_TOKEN`) is missing is named once in the run log and skipped. |

## Providers and credentials

`CLAUDE_BIN` / `CLAUDE_FLAGS`, `CODEX_BIN` / `CODEX_FLAGS` / `CODEX_PROFILE` /
`CODEX_MODE` (`interactive` \| `exec`), `KIMI_BIN` / `KIMI_FLAGS` / `KIMI_MODE`,
`AUGGIE_BIN` / `AUGGIE_FLAGS` / `AUGGIE_MODE` (`interactive` default \| `print`) /
`AUGGIE_MODEL` configure the agent CLIs; machine-trust flags belong in the **user
layer**, repo facts in the **project layer**. `AUGGIE_FLAGS` ships a long default of
`--allow-indexing --permission …` rules — dropping either half hangs a phase. Auggie
has no effort knob, reports credits rather than USD, has its Serena registration
check marked skipped rather than enforced, and is WSL2-only on Windows.

`<PROVIDER>_<PHASE>_MODEL` / `_EFFORT` route each phase (`BUILD`, `HANDOFF`,
`VERIFY`, `REPAIR`, `BUGFIX`, `CLEANUP`, `LINTFIX`, `COMMIT`, `PICK`, `PROOFREAD`) —
the *Models by phase* page and its presets edit these. `FALLBACK_PROVIDERS` names
the providers a run may fall through to.

Tracker credentials: `LINEAR_API_KEY` (enables fast direct GraphQL alongside MCP),
`JIRA_BASE_URL` / `JIRA_EMAIL` / `JIRA_API_TOKEN`, `AZURE_ORG_URL` / `AZURE_PAT`.
Forge credentials: a **Bitbucket Cloud** remote needs `BITBUCKET_EMAIL` and
`BITBUCKET_API_TOKEN` (a scoped Atlassian API token — app passwords were removed in
July 2026) and is **refused before the run spends anything** without them; a GitHub
remote needs neither and keeps using `gh auth`. No repository-admin grant is needed
for review trust any more — see `TRUSTED_REVIEWERS` and the ladder in
`references/operations.md` § Review feedback loop.

All of these live clear-text in the hub database like every other key — there is no
"safer file" to put them in, only the database's own permissions and the
`SECRET_REVEAL` audit on the way out.

## Cost and cadence

| Key | Meaning |
| --- | --- |
| `CLAUDE_PROMPT_CACHE_1H` | `hub` (default) \| `all` \| `off` — ask Claude Code for the 1-hour prompt-cache TTL. `hub` covers the hub's own sessions (interviews, challengers, publish, atlas, video); `all` adds every claude pipeline phase; `off` strips an inherited setting. No-op on subscription auth. |
| `CLAUDE_OUTPUT_STYLE` / `CLAUDE_<PHASE>_OUTPUT_STYLE` | `Concise` (default) \| `Default` \| empty — prose volume of every claude spawn; empty passes no style (the escape hatch for a repo's custom style). Per phase, empty = inherit. |
| `CLAUDE_<PHASE>_COMPACT_WINDOW` | Per-phase auto-compact window in tokens (100000–1000000) for claude phases. Unset (the default) leaves Claude Code's own behaviour. Codex, Kimi and Auggie ignore them. Re-read before each agent call (ADR 0069). |
| `AGENT_TIMEOUT` / `AGENT_STALL_WINDOW` / `AGENT_RETRIES` | `3600` s per agent call, `180` s with no output before a stall is declared, `2` retries. |
| `TEAM_SYNC` | `0` (default). `1` publishes this machine's lessons on a `refs/trau/team/<writer-id>` ref and folds teammates' back in. Refs only, never the working tree, and blameless — an unreachable remote is recorded for `trau doctor` and never pauses a run. |

## Ticket comments

`DELIVERY_COMMENTS`, `QUARANTINE_COMMENTS` and `RESET_COMMENTS` (all `1` by default)
control the ride-along notes trau leaves on a ticket at delivery, at quarantine and
at reset. Turning one off silences the note only — the status move and the label
swap still happen.
