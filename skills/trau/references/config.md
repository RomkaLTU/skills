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

Three exceptions to that ladder:

- **Hub-wide keys** — `AI_ASSESSMENT` and every `EXPERIMENTAL_*` key — resolve from
  the default, the user layer and the hub process environment only (ADR 0078,
  ADR 0111). No repo, project value or config import can set them.
- **A Project created in the hub starts on `TRACKER_PROVIDER=internal`** (ADR 0097).
  Credentials, a repo's saved tracker keys and a `TRACKER_PROVIDER` in the hub's
  environment do not change it, and that Project's saved `TRACKER_PROVIDER` outranks
  the environment. The user picks another tracker in the wizard or the Project's Edit
  form. Projects created before this rule keep the plain ladder.
- The license key (`TRAU_LICENSE_KEY`) is the one key the Settings page does not show;
  it lives under Account and connections and `trau license set` (stdin).

The user and project layers are edited from the hub's **Settings** page (every other
catalog key is web-editable, `SERVE_TOKEN` included — ADR 0055), the in-TUI settings
editor, `trau config import`, or the two validated setters:

- `trau config set <KEY>=<VALUE> [--repo <path>]` and the MCP `set_config` write the
  repo's **project layer** through the running hub, with the Settings page's
  validation: an unknown key or a value outside the key's options is refused and
  nothing is stored. `set_config layer=user` writes the user layer instead;
  `unset=true` removes the key from that layer. The answer carries `stored`,
  `effective`, `effective_layer` and `overridden_by` — a value the environment shadows
  still decides what a run reads.
- `EXPERIMENTAL_*` is written only by `set_config layer=user` (never `trau config
  set`); `AI_ASSESSMENT` by neither — the user switches it in Settings → AI assessment
  or the hub environment. Write either only when the user asks.

Read one back with `trau config get <KEY> [--repo <path>]` or `get_config`.

Two timing facts matter mid-run. **Phase routes are re-resolved before every agent
call** (ADR 0069): change a phase's model, effort, disallowed tools, output style or
compact window in Settings and the *next agent call of the same run* uses it. The
provider itself stays as settled when the ticket started, and budgets, skills and
`VERIFY_EFFORT` still settle at process start. And a **Models by phase Preset**
(ADR 0063, provider-owned since ADR 0081 — names are unique per Provider) applied
from a repo's **Models** page writes the project layer; from the global page, the
user layer. Applying a Preset never writes `PROVIDER`.

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
| `.trau/checks/*.yaml` | Repo-defined verify checks (`VERIFY_CHECKS`). |
| `<ADR_DIR>/` (`docs/adr`) | The architecture decision records `ADR_POLICY` makes interviews, build, repair and verify follow (see Loop behavior). Created only when the first ADR is written. |

The plugin system (`PLUGINS`, `.trau/plugins/*.json`, the Uizze plugin) was removed
(ADR 0091); those keys and files do nothing. Trau never edits a target repo's tracked
`.gitignore` any more: it keeps its local files out of git through
`.git/info/exclude` (ADR 0138), and an old committed trau block is left as it is.

## Tracker and eligibility

What decides whether the picker sees a ticket at all:

| Key | Meaning |
| --- | --- |
| `TRACKER_PROVIDER` | `linear` \| `jira` \| `azure` \| `github` \| `internal` (trau's own hub-store issues — the automatic fallback when no external tracker is configured, and what every hub-created Project starts on; see Layering). |
| `LINEAR_TEAM` | Team name / Jira project key / Azure team project / GitHub repo slug (Jira and Azure fall back to `PROJECT`). Empty = the onboarding wizard on the next interactive run. |
| `ISSUE_PREFIX` | Ticket-id prefix (`COD`, `ENG`, …) for parsing, branch inference and sentinels. Empty = derived from the team key, falling back to `COD`; Azure leaves it empty (work items go by number). `trau doctor` *issue prefix* flags one that contradicts the tracker key. |
| `INTERNAL_ISSUE_PREFIX` | Prefix that internally-filed issues are minted under (`LOOP` → `LOOP-42`). Empty = the repo directory name uppercased, then `ISSUE`, then `TRAU` — always skipping the tracker's own key; on the internal tracker `ISSUE_PREFIX` names minted ids instead. An internal issue carved from a tracker ticket carries an `origin`, and delivery names the *origin* key on branch, commit and PR — so a forge search for `LOOP-42` finds `SAVE24-761` instead. |
| `READY_LABEL` | Default `ready-for-agent` — what makes a ticket eligible to pick. |
| `PICK_LABELS` | Empty (default). Comma-separated extra labels **every** ticket must carry, on top of `READY_LABEL`, before the loop picks it. |
| `QUARANTINE_LABEL` | Default `needs-human` — where failed tickets land; also the label to file human-attention tickets under. |
| `QUEUED_LABEL` | Default `queued` — mirrored onto tickets waiting in the hub queue; the hub heals drift on every sync. Empty = no writes (worth doing per machine when several people's hubs share one tracker). |
| `SPLIT_LABEL` | Default `needs-split` — the managed label marking a ticket a **human** should split before the loop builds it. A triage label (`needs-triage`, `needs-info`, this one) files a ticket into the Inbox rather than the queue, and **queuing, running or "make ready" strips it** — a triage label put back on a queued ticket is removed on the next sync tick. |
| `PROJECT` | Ownership guard: when set, the loop only picks tickets in this tracker project — protects multi-repo trackers from cross-repo picks. Empty = no guard. |
| `EPIC_ADOPT_PARENT` | `queued` (default) \| `always` \| `never` — when a ticket queued on its own builds on its tracker parent's epic branch instead of the base. |

"Why didn't it pick my ticket" is almost always answered here: wrong label, a missing
`PICK_LABELS` label, wrong state, a blocker relation (`blocked_by` edges are
enforced — across Projects too when both sit in one hub Workspace, ADR 0139), another repo's
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
| `REQUIRE_CI` | `auto` (default) = gate merges on CI when the repo's own GitHub Actions or Bitbucket Pipelines configuration answers a pull request into the PR's base; a repo with no pull-request pipeline waits one `CI_TIMEOUT` and then merges with a warning (one whose pipelines target other branches merges after a short grace). `1` insists on checks (absent ones time the run out — set `0` on a push-only repo instead). Merge-affecting. |
| `CI_TIMEOUT` / `CI_POLL` / `EXPECTED_CHECKS` | How long to wait for CI, how often to poll, which checks to insist on. |
| `MAX_REPAIRS` / `MAX_BUGFIXES` | Repair attempts default `2`. **Bugfix attempts default to unlimited** (empty or `0`): a default-config run keeps bugfixing until verify passes or a budget cap stops it, and only an explicit `N` makes verify give up and quarantine. |
| `MAX_ITERATIONS` | Tickets per run; default unlimited (`--max 0`). An epic child loop that hits a cap with open children left reports `capped` and re-queues — not a quarantine. |
| `REVIEW_GATE` | `0` (default). `1` holds a green PR short of the auto-merge until its reviewers say something — an approval merges it, changes requested run the fix rounds and come back to the gate. Applies to an epic's release PR too. No timeout; it polls at `CI_POLL`. `AUTO_MERGE=0` supersedes it. Merge-affecting. |
| `MAX_REVIEW_ROUNDS` | `10` — rounds spent answering a PR's review feedback (fix or decline each thread, reply, re-request review). Exhausted on a **ticket** PR, the run quarantines the disagreement; an epic PR parks `awaiting-changes` instead. |
| `REVIEW_RESOLVE` | `reviewer` (default) \| `trau` — who closes a thread trau fixed: reply and leave it open for the reviewer, or resolve it. Declined threads stay open either way. |
| `TRUSTED_REVIEWERS` | Comma-separated forge identities (GitHub login; Bitbucket `account_id` or `{uuid}`) whose feedback trau acts on regardless of forge permissions — rung 1 of the trust ladder (ADR 0064). Feedback from an author no rung can vouch for **parks** the row `awaiting-changes` until someone is added here or decides on the PR. |
| `QA_GATE` | `0` (default). `1` holds every run after green CI and before the merge, at a durable `awaiting-qa` row a person releases with **Approve** (`approve_qa`) or sends back with **Reject** (`reject_qa`, notes required; two fix rounds, a third reject settles the row `failed`). Not a drain hold: the lane is freed while it waits and the worktree and its app stay up. An epic holds once, at its release. A queued item's own `qa_gate` (`on` \| `off` \| empty; the Queue's *Hold for QA*) overrides this in both directions. Both onboarding wizards ask for it once. |
| `ADR_POLICY` / `ADR_DIR` | `1` / `docs/adr`. Interviews, planning, build and every repair path consult the repo's ADRs and record new durable decisions; cold verify must return a structured ADR result and **fails the verdict** on a missing ADR or a missing/malformed result, whatever `VERIFY_CHECKS` or `VERIFY_EFFORT` say. A diff contradicting an accepted ADR the issue does not authorize **pauses** the run (`ADR conflict needs human input: …`) until a person settles it with `settle_adr_conflict` / `trau adr authorize\|keep` — editing the issue does not clear it. `ADR_DIR` must stay inside the repo; a bad one pauses the run (`ADR policy cannot run: …`). `0` drops the instructions and the gate. |
| `COMMIT_TEMPLATE` / `PR_TITLE_TEMPLATE` / `BRANCH_TEMPLATE` | Full-control message and name formats; empty = trau's own (`feature/{{.Ticket}}-{{.Slug}}`). A `BRANCH_TEMPLATE` without `{{.Ticket}}` or `{{.ID}}` refuses the config load, and so does any template naming an unknown placeholder. |
| `PR_BODY_TEMPLATE_FILE` | Path (relative to the PR's repo root) to a Markdown `text/template` for PR bodies. A missing, empty or unrenderable file **fails the run** — there is no fallback to the built-in body. |
| `CLAUDE_DISALLOWED_TOOLS` | `Agent,Workflow,Bash(git push:*),Bash(gh pr create:*)` — delivery commands blocked in every claude phase (the loop delivers, not the agent). Per-phase `CLAUDE_<PHASE>_DISALLOWED_TOOLS`. Codex/Kimi/Auggie have no deny list; the prohibition is prompt-only there. |

The pick gate and `PICK_ROUNDS` no longer exist (ADR 0059).

## AI assessment and models by complexity

| Key | Meaning |
| --- | --- |
| `AI_ASSESSMENT` | `0` (default). **Hub-wide**, user layer or hub environment only, needs an active license key. The one consent for the Trau assessment service: Complexity badges and readiness signals, lesson classification and recall, skill relevance, grill question checks, duplicate checks of proposed tickets, repair-stall checks. On, the hub sends ticket titles, descriptions and comments, verify failure evidence, recalled lessons, package signals and grill questions (the service does not retain them). No answer changes a pick or the Queue order. The retired per-feature assessment keys do nothing. |
| `MODELS_BY_COMPLEXITY` | `0` (default, per repo, needs `AI_ASSESSMENT`). A ticket with a usable Complexity score runs under the saved Preset its band maps to — `COMPLEXITY_LOW_PRESET` / `_MEDIUM_PRESET` / `_HIGH_PRESET`, mapped on the Models page and looked up inside the run's Provider. The band is fixed at ticket start; no score, no mapping or no such Preset keeps the configured Routes. Ticket text never names a Model. Turning it on for a claude or codex repo seeds missing `Complexity low` / `Complexity high` Presets into empty band keys. Run log: `complexity 7 -> band high -> Preset "deep"`. |
| `COMPLEXITY_LOW_MAX` / `COMPLEXITY_HIGH_MIN` | `3` / `7` — band limits on the 1–10 score; an invalid pair falls back to 3 and 7 with a warning. |
| `COMPLEXITY_ESCALATE_AFTER` | `2` (`0` = off; needs only `MODELS_BY_COMPLEXITY`). After that many failed verify rounds every later agent call of the ticket runs one band higher, capped at high; no band counts as medium. Survives a resume. `trau --complexity-band <band>` (or `band` on a Queue add) pins one run's band without sending ticket text. |

## Budgets

Hard spend rails — the loop stops rather than crossing them:

`MAX_TICKET_USD`, `MAX_TICKET_TOKENS`, `MAX_DAILY_USD`, `MAX_DAILY_TOKENS`. All
empty by default. A ticket reaching a per-ticket cap is quarantined with a
cost-overrun note and the loop moves on; a per-day cap stops the run cleanly. Under
`QUEUE_AUTO_DRAIN=1` a row that comes back `capped` holds the drain under the
`daily-cap` gate until local midnight, so a standing drain does not re-spawn into the
same wall.

Three things to know before reading a number: the **per-day totals also count the
hub's own sessions** — interviews, challengers, publish, atlas — because they
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
| `BROWSER_VERIFY` | `auto` (default — a UI slice should be driven; one that was not is recorded as a note) \| `always` (an undriven UI slice is re-verified once and then **pauses** `browser_verify`, as does a missing or unanswering `APP_URL`) \| `never`. A backend-only slice is not-applicable at every level. |
| `BROWSER_ISOLATION` | `managed` (default): build always gets a dedicated headless browser, verify / repair / bugfix when the slice has a UI surface, and every other phase has the shared-browser env (`BU_CDP_*`) stripped so no agent drives the user's browser. `attach` is the old shared-browser behaviour. Why no window opens and why two lanes never share tabs. |
| `BROWSER_HARNESSES` | `agent-browser,browser-harness` (default) — ordered managed harnesses; the first is primary, later ones are startup fallbacks, a single entry disables fallback. A phase left with no harness runs with **no browser** rather than falling back to yours. `trau browser setup` provisions both, `trau browser status` reports readiness. The single-value `BROWSER_HARNESS` is retired. Missing OS libraries pause the run `tool_unavailable` with the fix `trau browser setup --system` — which installs OS packages and needs a person at that machine; never auto-resumed. |
| `APP_URL` / `APP_URLS` | Where browser verify points; `APP_URLS` maps monorepo package workspaces to URLs. |
| `VERIFY_PANEL` / `VERIFY_PANEL_POLICY` | Cross-vendor verify: N isolated verifiers from different providers, merged `unanimous` \| `majority` \| `any-pass`. |
| `VERIFY_EFFORT` | `high` \| `medium` (default) \| `low` — how strictly verify grades a slice. It narrows **both** what the verifier investigates and what can fail the verdict, so a lower level is cheaper and faster, not just more lenient: `high` is full adversarial QA, `medium` the rubric plus regressions in what the slice touched, `low` the rubric contract alone. There is no `off`. Not the same knob as `CLAUDE_VERIFY_EFFORT` / `CODEX_VERIFY_EFFORT`, which set the *provider's* reasoning effort for the phase. |
| `TEST_EFFORT` | `low` (default) \| `off` \| `medium` \| `high` — how much test work build is asked for (ADR 0041). |
| `VERIFY_PROOFS` / `PROOF_RETENTION_DAYS` | `on` / `14`. Browser verify saves key **screenshots** only (video and traces were removed, ADR 0089). Destination: `attachments` (GitHub, `gh` ≥ 2.99 — PR attachments, never pruned; a rejected upload retries the PR once without proofs), else the `trau-proofs` branch, else `hub` (kept, no PR link). Retention applies to the `trau-proofs` branch only and is the **hub's own** value — a project-layer value is not read; `0` = forever. `trau doctor` and `GET /api/v1/repos/{repo}/proof-storage` name the destination and any fallback. |
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

A repo with **no remote** delivers locally: the ticket branch is squash-merged into the
base where it is checked out — under `WORKTREES=1`, the primary checkout. Trau checks
that checkout before the build and again at the merge (ADR 0097), and **pauses** the
run (`the local merge into <base> is held …`) when it is on another branch or detached,
mid-merge or mid-rebase, has staged changes, or has uncommitted paths the ticket branch
also writes. Unrelated edits and untracked files are fine. That work is the user's —
never commit, move or discard it; `resume_run` checks again.

## The hub (`SERVE_*`)

| Key | Meaning |
| --- | --- |
| `SERVE_BIND` / `SERVE_PORT` | Default `127.0.0.1:8728`. |
| `SERVE_TOKEN` | Required the moment the bind leaves loopback — the hub refuses to start exposed without it; all requests then need `Authorization: Bearer`. Editable from Settings; read at serve start. |
| `SERVE_ALLOW_REGISTER` | `0` (default): on an exposed hub, (un)registering repos, `add_project_repo`, project CRUD, filesystem browse/discover and other widen-the-footprint routes are refused even with the token — a leaked token can't widen where agents run. |
| `SERVE_WORKSPACE` | An extra **startable** allowlist. The hub may start (and stop) loops in the repos **Registered** with it plus whatever this key lists; a repo it merely discovered stays observe-only for both start and stop (`403 repo is observe-only`). Empty — the default — means Registered repos only. It is not a list of the repos the hub serves, and it has nothing to do with hub-UI **Workspaces** (ADR 0073 — a per-browser grouping of Projects with no config key) or `APP_URLS`' *package workspaces*. |
| `SERVE_REMOTE` | `off` (default) \| `tailscale` — publish the hub on the tailnet's HTTPS port, bind still loopback, no port opened to the internet. `trau hub remote on\|off` writes this key; the hub reconciles the forward against it at start and about once a minute after. |
| `HUB_PEER_URL` / `HUB_PEER_TOKEN` / `HUB_PEER_ID` | Runner presence. Empty (default) = no outbound request. Set `HUB_PEER_URL` (a central hub's base URL) and this hub heartbeats to it at start and every 30 s: host, version, its off-machine URL, and per registered repo the draining state, live lanes and last tracker sync — no ticket text, code or credentials. `HUB_PEER_TOKEN` (a secret) is the bearer the heartbeat presents — needed when the central hub binds off loopback with a `SERVE_TOKEN`; `HUB_PEER_ID` is minted on the first heartbeat — changing it lists the machine twice. |
| `SERVE_AUTOSTART` | `1` (default): the first interactive `trau` session brings the hub up first. `--no-serve` disables it for one run. |
| `SERVE_OPEN` | `1` (default): a fresh hub spawn (and `trau hub start`) opens the browser. |
| `SECRET_REVEAL` | `off` (default) \| `admin` — arms the audited one-secret-per-call reveal path (`reveal_secret`, `--reveal`). Until a repo sets it, the tool is absent from the hub's `tools/list`. |
| `HUB_SELF_RELOAD` | `0` (default). `1` lets **the trau source checkout** ask the hub to restart onto the binary it builds — `HUB_RELOAD_BUILD_CMD` (default `make build`), `HUB_DEV_BINARY` (default `bin/trau`), `HUB_RELOAD_PULL` (fast-forward first). Any other repo is refused and never sees these keys. |
| `QUEUE_AUTO_DRAIN` | `0` (default). **Standing drain**: `1` keeps this repo's drain armed after the queue runs dry, and every issue sync (`SERVE_SYNC_INTERVAL`, 120 s) enqueues the unblocked leaf tickets carrying `READY_LABEL` and starts them — no one presses Start, and it arms with `on_fault=skip`. It spends tokens with nobody watching; set it only when the user asks. An armed, empty standing drain reads `held_gate: idle`. |
| `QUEUE_AUTO_RESUME` / `QUEUE_AUTO_RESUME_TRIES` | `0` / `2`. With auto-resume on, the hub re-attempts an item whose run **paused** (a provider wall, an unreachable hub, a dialog, …) once a backoff passes — 2 minutes × attempt — and gives up after N tries. Never a fault, a stop, a `held` row, an **ADR-conflict** pause or a pause waiting on `trau browser setup --system`. The plan lives in the hub's memory, so a hub restart forgets it and the item stays parked. A crashed epic release gets two tries regardless. |
| `HOOK_GENERIC_SECRET` / `HOOK_SENTRY_SECRET` / `HOOK_NIGHTWATCH_SECRET` | Webhook intake, per repo; empty (default) = the route answers 404. Each secret (HMAC-SHA256 of the raw body; a mismatch is 401) enables `POST /api/v1/repos/<repo>/hooks/{generic,sentry,nightwatch}`. An *opened* event **files an internal bug ticket** labelled `READY_LABEL` + `bug` + the source, **queues it and arms the drain** (`on_fault=skip`); a repeat open comments, *reopened* re-queues an idle ticket, *resolved* dequeues and cancels it unless a run holds it. `SENTRY_API_TOKEN` (`event:read`, a secret) adds the latest event's stack trace from `SENTRY_BASE_URL` (default `https://sentry.io`). |
| `UPDATE_CHECK` / `TRAU_LICENSE_KEY` | `1` — check `get.trau.sh` once a day for a newer release. The binary is public (ADR 0106): the update check, `trau update`, the Hub page's Updates section and `install.sh` need **no key**. The key (a secret, hidden from Settings) is what the account profile and entitlement refresh send; `trau license set` reads it from stdin. |
| `SKILL_UPDATE_CHECK` | `1` — once a day, compare the globally installed trau operator skill (`RomkaLTU/skills@trau`) with upstream and offer the update in Settings. Reads the skills.sh lock of the hub's OS user, never writes it, installs nothing on its own; needs no license. |
| `CRASH_REPORTS` | `1` (default): a panic or pipeline fault sends one crash event to trau's Sentry (ADR 0057). `0` or `DO_NOT_TRACK=1` disables; `trau doctor` *crash reports* states which. Unrelated to the manual, unredacted `trau dump`. |
| `NOTIFY` / `HOLD_REMINDER_HOURS` | `0` / `24`. `NOTIFY=1` fires a native desktop notification for every bell item — paused / faulted / quarantined runs, PRs awaiting merge or QA, changes requested, hold reminders, an epic parked or delivered, interview questions, a finished publish. Rows sitting on a human (`awaiting-merge`, `awaiting-changes`, `awaiting-qa`, `no-change`) are re-notified every `HOLD_REMINDER_HOURS` (0 = once). A reminder never moves a row. |
| `EXPERIMENTAL_PRODUCT` | `0`. Hub-wide (user layer only): shows the experimental Product module, drawn from sample data. The only `EXPERIMENTAL_*` key; switched in Settings → Experimental. |

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
`VERIFY`, `REPAIR`, `BUGFIX`, `CLEANUP`, `COMMIT`, `PICK`, `PROOFREAD`) — the
**Models** page (Models by phase, Models by complexity) and its Presets edit these.
The `*_LINTFIX_*` route keys are retired: the lint-fix phase runs `LINT_FIX_CMD` only,
no agent. `FALLBACK_PROVIDERS` names the providers a run may fall through to.

Tracker credentials: `LINEAR_API_KEY` (enables fast direct GraphQL alongside MCP),
`JIRA_BASE_URL` / `JIRA_EMAIL` / `JIRA_API_TOKEN` (a classic, unscoped token),
`AZURE_ORG_URL` / `AZURE_PAT`. Forge credentials: a **Bitbucket Cloud** remote needs a
connection (below) or `BITBUCKET_EMAIL` + `BITBUCKET_API_TOKEN` (a scoped Atlassian
API token — app passwords were removed in July 2026) and is **refused before the run
spends anything** without one; a GitHub remote needs neither and keeps using
`gh auth`. No repository-admin grant is needed for review trust any more — see
`TRUSTED_REVIEWERS` and the ladder in `references/operations.md` § Review feedback
loop.

**Service connections** (ADR 0139–0142) are OAuth sign-ins the hub holds per tracker
account — `trau connect linear|jira|bitbucket`, `trau connections`, Settings →
Connections, `list_connections` / `test_connection` / `remove_connection`. Only the
user can approve the consent page, and no surface returns a token.

| Key | Meaning |
| --- | --- |
| `LINEAR_CONNECTION` | Account label (or id) of the Linear connection a repo uses; empty picks the only one. A resolved connection beats `LINEAR_API_KEY`. `LINEAR_OAUTH_CLIENT_ID` ships a built-in default; empty = no Linear sign-in. |
| `JIRA_CONNECTION` | Label or id; empty picks the only one reaching `JIRA_BASE_URL`. Beats `JIRA_EMAIL` / `JIRA_API_TOKEN`; while `get.trau.sh` is unreachable it keeps its last token until that expires, then falls back to them. Sign-in goes through `get.trau.sh` (needs the license key) unless `JIRA_OAUTH_CLIENT_ID` + `JIRA_OAUTH_CLIENT_SECRET` name the operator's own Atlassian 3LO app (callback `<hub origin>/api/v1/oauth/jira/callback`). |
| `BITBUCKET_CONNECTION` | Label or id; empty picks the only one reaching the remote's workspace. Beats `BITBUCKET_EMAIL` / `BITBUCKET_API_TOKEN` and falls back to them when it needs a new sign-in. Requires the operator's own OAuth consumer — `BITBUCKET_OAUTH_CLIENT_ID` / `_SECRET` (`pullrequest:write`, `repository:write`, callback `<hub origin>/api/v1/oauth/bitbucket/callback`), which reaches only the workspace that created it. The same connection authenticates git over https to `bitbucket.org` via `trau git-credential` (internal — never run it). |

GitHub has no hub-held token: Settings → Connections runs `gh auth login` in the hub,
and a separate button runs `gh auth setup-git` (writes the user's global git config —
ask first).

All of these keys live clear-text in the hub database like every other key — there is
no "safer file" to put them in, only the database's own permissions and the
`SECRET_REVEAL` audit on the way out.

## Research and interviews

| Key | Meaning |
| --- | --- |
| `TWG_ENABLED` / `TWG_BIN` | `0` / `twg` (per repo, Jira trackers only). Gives that repo's Research and Interview sessions two read-only Teamwork Graph reads — one related-context read and up to three document reads per session — against `JIRA_BASE_URL`. Session tools only, not hub MCP tools. Trau never installs, signs in to or updates `twg`: the user does, as the hub's OS account, with a read-only grant. Reads may use Rovo credits, and selected text reaches the AI Provider. Turn on only when the user asks. |
| `PROJECT_CREATION_RESEARCH_PROVIDER` / `_MODEL` | Provider (`claude` default \| `codex`) and model for the creation Research a New Project runs before any repo exists; separate from `GRILL_PROVIDER`. |

## Cost and cadence

| Key | Meaning |
| --- | --- |
| `CLAUDE_PROMPT_CACHE_1H` | `hub` (default) \| `all` \| `off` — ask Claude Code for the 1-hour prompt-cache TTL. `hub` covers the hub's own sessions (interviews, challengers, publish, atlas and the like); `all` adds every claude pipeline phase; `off` strips an inherited setting. No-op on subscription auth. |
| `CLAUDE_OUTPUT_STYLE` / `CLAUDE_<PHASE>_OUTPUT_STYLE` | `Concise` (default) \| `Default` \| empty — prose volume of every claude spawn; empty passes no style (the escape hatch for a repo's custom style). Per phase, empty = inherit. |
| `CLAUDE_<PHASE>_COMPACT_WINDOW` | Per-phase auto-compact window in tokens (100000–1000000) for claude phases. Unset (the default) leaves Claude Code's own behaviour. Codex, Kimi and Auggie ignore them. Re-read before each agent call (ADR 0069). |
| `AGENT_TIMEOUT` / `AGENT_STALL_WINDOW` / `AGENT_RETRIES` | `3600` s per agent call, `180` s with no output before a stall is declared, `2` retries. |

Git-ref team synchronization was removed (ADR 0113): `TEAM_SYNC` is no longer a key
(a stale value is ignored; `get`/`set` treat it as unknown), lessons and run history
are local only, and existing `refs/trau/team/*` refs are left untouched as unused data.
File-based sharing through `.trau/config.team.ini` and its drift checks is unaffected.

## Ticket comments

`DELIVERY_COMMENTS`, `QUARANTINE_COMMENTS` and `RESET_COMMENTS` (all `1` by default)
control the ride-along notes trau leaves on a ticket at delivery, at quarantine and
at reset. Turning one off silences the note only — the status move and the label
swap still happen.
