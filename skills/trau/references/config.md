# Configuration — what an operator needs to know

The key catalog built into the binary is the one per-key reference (ADR 0157):
`trau config list [--json]` prints every key with its settings section and default
summary, `trau config describe <KEY> [--json]` one key's full contract (default, seed
default, options, shareable, merge-affecting, retired). Both read the catalog only — no
hub, repo or value — and run from any directory. The hub's Settings page carries the
same catalog. This reference covers the layering model and the knobs that answer
operator questions — "why didn't it pick my ticket", "why is the drain serial", "why
did it stop at the PR", "why did the drain refuse to arm". Written against trau
v11.7.0; defaults and phase Models change across releases, so `describe` before you
copy a value.

## Contents

- [Layering](#layering)
- [Repo-committed files](#repo-committed-files)
- [Tracker and eligibility](#tracker-and-eligibility)
- [Loop behavior](#loop-behavior)
- [Lessons and calibration](#lessons-and-calibration)
- [AI assessment and models by complexity](#ai-assessment-and-models-by-complexity)
- [Budgets](#budgets)
- [Verify](#verify)
- [Worktrees and parallelism](#worktrees-and-parallelism)
- [The hub (`SERVE_*`)](#the-hub-serve_)
- [Providers and credentials](#providers-and-credentials)
- [Research, interviews and prototypes](#research-interviews-and-prototypes)
- [Cost and cadence](#cost-and-cadence)
- [Ticket comments](#ticket-comments)
- [Additional controls in the current binary](#additional-controls-in-the-current-binary)

## Layering

Verbatim from `trau --help`, lowest to highest precedence:

```
defaults < user layer < ./trau.ini < project layer < environment < flags
```

1. **built-in defaults** — the catalog's `Default`, or the seed default code falls back
   to (`describe` also names a *runtime fallback* resolved when the run needs it).
2. **the user layer** — this machine's baseline (provider flags, machine-trust
   knobs, the license key). Not a file: since ADR 0051 it is rows in the hub
   database, scope `user`.
3. **`./trau.ini`** in the cwd (or the file `TRAU_ENV` names) — the one config *file*
   layer left, read and never written.
4. **the project layer** — this repo's own facts, keyed by absolute repo root. Rows
   in the same hub database (scope `project`), and it always beats the user layer,
   so a machine-wide credential can never shadow a repo's own.
5. **environment variables** — any key, or its collision-safe `TRAU_<KEY>` alias
   (`TRAU_PROVIDER` beats a generic `PROVIDER` in the shell; an empty `TRAU_<KEY>`
   does not win).
6. **CLI flags** (`--repo`, `--provider`, `--max`, …)

Exceptions to that ladder:

- **Hub-wide keys** — `AI_ASSESSMENT`, `ASSISTANT_REPORTS`, `ARTIFACT_PUBLIC_SHARE`,
  `CALIBRATION_AUTO_APPLY`, `HOSTED_REPO_REFRESH` and every `EXPERIMENTAL_*` key —
  resolve from the default, the user layer and the hub process environment only
  (ADR 0078, ADR 0111). A write to any other layer is refused; no repo, project value
  or config import can set them. `ASSISTANT` (the Assistant launcher) reads the same
  way.
- **A Project created in the hub starts on `TRACKER_PROVIDER=internal`** (ADR 0097).
  Credentials, a repo's saved tracker keys and a `TRACKER_PROVIDER` in the hub's
  environment do not change it, and that Project's saved `TRACKER_PROVIDER` outranks
  the environment. Projects created before this rule keep the plain ladder; with no
  layer setting it, a repo runs on Linear only when `LINEAR_TEAM` or `LINEAR_API_KEY`
  is set, otherwise on the internal tracker.
- **Licence-carried keys** — `ALLOWED_PROVIDERS`, `REQUIRE_PROVIDER_LOGIN` — come from
  the signed entitlement; a stored value is ignored and the environment can only narrow
  or tighten them (see Additional controls).
- **Sealing keys** — `TICKET_SECRETS_KEY`, `ACCOUNT_SECRETS_KEY` — are read only from
  `TRAU_TICKET_SECRETS_KEY` / `TRAU_ACCOUNT_SECRETS_KEY` at serve start; a stored value
  is ignored and the settings surface refuses the write (see The hub).
- The license key (`TRAU_LICENSE_KEY`) is the one key the Settings page does not show;
  it lives under Account and connections and `trau license set` (stdin).

The user and project layers are edited from the hub's **Settings** page, the in-TUI
settings editor, `trau config import`, or the validated setters:

- `trau config set <KEY>=<VALUE> [--repo <path>]` and the MCP `set_config` write the
  repo's **project layer** through the running hub, with the Settings page's
  validation: an unknown key, a value outside the key's options, or a model–effort pair
  the model does not support is refused and nothing is stored. `AUTO_MERGE`,
  `QA_GATE` and `REVIEW_GATE` are unknown keys — the refusal says to set `DELIVERY`.
  Other retired keys (`EPIC_FLOW`, every `*_LINTFIX_*`, `COMPLEXITY_*_PRESET`,
  `BROWSER_HARNESS`, `WEB_LAYOUT`, `GRILL_AUTOCOMPLETE_*`, `ASSISTANT_STALL_MINUTES`,
  `ASSISTANT_TRIAGE_EFFORT`) stay in the catalog with a `retired` note naming the
  replacement, are hidden from Settings, and do nothing. `trau config unset <KEY> [--repo <path>]` removes the project-layer row.
  `set_config layer=user` writes the user layer instead; `unset=true` removes the key
  from that layer. The answer carries `stored`, `effective`, `effective_layer`,
  `overridden_by` and, on a Folder repo, `child_shadow` (child files that override the
  key) — a value the environment shadows still decides what a run reads.
- Hub-wide keys are written only with `set_config layer=user` or in Settings (Settings
  → AI assessment, → Experimental, …); `trau config set` refuses them. Each changes what
  leaves the machine or what the hub does unattended — write one only when the user
  asks.

Read one back with `trau config get <KEY> [--repo <path>]` (raw value on stdout,
non-zero exit when unset) or `get_config`.

Two timing facts matter mid-run. **Phase routes are re-resolved before every agent
call** (ADR 0069): change a phase's model, effort, disallowed tools, output style or
compact window in Settings and the *next agent call of the same run* uses it. The
provider itself stays as settled when the ticket started (a live `switch_provider`
is the exception — it restarts the active agent call), and budgets, skills and
`VERIFY_EFFORT` still settle at process start. And a **Models by phase Preset**
(ADR 0063, provider-owned since ADR 0081 — names are unique per Provider) applied
from a repo's **Models** page writes the project layer; from the global page, the
user layer. Applying a Preset never writes `PROVIDER`.

The old home-directory and per-repo `.trau.ini` files are **not layers any more**. A
leftover one is imported once and renamed `.trau.ini.migrated`, and `trau doctor`
reports what happened under *config layers*, *retired config files*, *migrated config*
and *config shadowing*. `trau config import --from-backup [--dry-run]` puts a migrated
value back — add-only: a value stored since the migration (an emptied one included) is
kept. A `.trau.ini` inside a repo directory survives only as an opt-in
*per-directory override* (ADR 0019): a monorepo package workspace's file for keys
resolved after the diff is known (`LINT_FIX_CMD`), and a Folder child's file for its
`FORGE`, `BASE_BRANCH` and worktree keys. `describe` says when a key reads one.

Keys ARE the environment-variable names — `PROVIDER=` and `TRAU_PROVIDER` in the
shell are the same knob. The file format, where a file is still involved, is a flat
INI subset (`KEY=value`, `#` comments). An on/off key takes `1`/`true`/`yes`/`on` or
`0`/`false`/`no`/`off`; anything else warns and keeps the default.

**Config secrets are stored clear-text** in the hub database, and plain `trau config
get` prints them as typed; the database file's permissions are the trust boundary. The
*hub* side hands nothing back — `get_config`, the config API and Settings report a
secret as "set" only — unless `SECRET_REVEAL=admin` arms the audited reveal path
(`reveal_secret`, `trau config get <KEY> --reveal --reason "<why>"`, `trau secret get
<ID> NAME --reveal --reason …`), each call of which writes a `secret_revealed`
forensics event. Secret keys are left out of `trau config export` and redacted from
logs and tracker prose. Ticket secrets, terminal passwords and service-connection
tokens are different: sealed with `TICKET_SECRETS_KEY` (ADR 0275), never clear-text.

## Repo-committed files

Beside the layers, a few files under the repo change behaviour when present:

| File | Role |
| --- | --- |
| `.trau/config.team.ini` | Written by `trau config export [--out <file>] [--section <name\|slug>]`, applied by `trau config import [<file>] [--section …] [--dry-run]` (add-and-update, never deletes). Export carries only `shareable` keys; credentials are named in its checklist without values. Once committed, any drift between it and the effective config is a `trau doctor` *team config* warning; drift on a **merge-affecting** key (`DELIVERY`, `REQUIRE_CI`) fails doctor, makes a run print a warning, makes `start_queue` refuse until `acknowledge_drift` repeats the set, and holds a mid-drain queue under the `team-drift` gate. |
| `.trau/worktree.yaml` | `copy:` replaces `WORKTREE_COPY`; `setup:` (named steps, per-step `timeout`, default 15 m) replaces `WORKTREE_SETUP_CMD`; `app:` (`serve`, `run`) replaces `APP_SERVE` + `APP_START_CMD`. Each section takes over only when present; a file that does not parse **faults the run** rather than falling back. `trau worktree init` drafts it, `trau doctor` *worktree file* validates it. |
| `.trau/checks/*.yaml` | Repo-defined verify checks (`VERIFY_CHECKS`); any custom check replaces the built-in set. |
| `<ADR_DIR>/` (`docs/adr`) | The architecture decision records `ADR_POLICY` makes interviews, build, repair and verify follow (see Loop behavior). Created only when the first ADR is written. |

The plugin system (`PLUGINS`, `.trau/plugins/*.json`, the Uizze plugin) was removed
(ADR 0091); those keys and files do nothing. Trau never edits a target repo's tracked
`.gitignore` any more: it keeps its local files out of git through
`.git/info/exclude` (ADR 0138), and an old committed trau block is left as it is.

## Tracker and eligibility

What decides whether the picker sees a ticket at all:

| Key | Meaning |
| --- | --- |
| `TRACKER_PROVIDER` | `linear` (default) \| `jira` \| `azure` \| `github` \| `internal` (trau's own hub-store issues — the fallback when no external tracker is configured, and what every hub-created Project starts on; see Layering). Switching to `internal` drops the repo's mirrored tracker issues and is refused while the queue holds tracker work. |
| `LINEAR_TEAM` | Team name / Jira project key / Azure team project / GitHub repo slug (Jira and Azure fall back to `PROJECT`). Empty = the onboarding wizard on the next interactive run. |
| `ISSUE_PREFIX` | Ticket-id prefix (`COD`, `ENG`, …) for parsing, branch inference and sentinels. Empty = derived from the team key; Azure leaves it empty (work items go by number). `trau doctor` *issue prefix* flags one that contradicts the tracker key. |
| `INTERNAL_ISSUE_PREFIX` | Prefix that internally-filed issues are minted under (`LOOP` → `LOOP-42`). Empty = the repo directory name, then `ISSUE`, then `TRAU` — always skipping the tracker's own key; on the internal tracker `ISSUE_PREFIX` names minted ids instead. An internal issue carved from a tracker ticket carries an `origin`, and delivery names the *origin* key on branch, commit and PR — so a forge search for `LOOP-42` finds `SAVE24-761` instead. |
| `READY_LABEL` | Default `ready-for-agent` — what makes a ticket eligible to pick. A ticket carrying a `trau-hold-v<N>` development-hold label is never picked, whatever this says. |
| `PICK_LABELS` | Empty (default). Comma-separated extra labels **every** ticket must carry, on top of `READY_LABEL`, before the loop picks it. |
| `QUARANTINE_LABEL` | Default `needs-human` — where failed tickets land; also the label to file human-attention tickets under. |
| `QUEUED_LABEL` | **Empty (default) = no writes**: the hub Queue page is the source of truth and the queue is not mirrored to the tracker (ADR 0315–0317). Set, the hub alone owns the label: it goes on while a ticket waits, comes off when its run starts or it leaves the queue, and each sync heals drift. On Jira every label write emails watchers. |
| `SPLIT_LABEL` | Default `needs-split` — the managed label marking a ticket a **human** should split before the loop builds it. A triage label (`needs-triage`, `needs-info`, this one) files a ticket into the Inbox rather than the queue, and **queuing, running or "make ready" strips it** — a triage label put back on a queued ticket is removed on the next sync tick. |
| `BUSINESS_LABEL` | Default `business-requirement` — added by a Business specification approval to every ticket it creates or updates; empty = no label and no signal. |
| `PROJECT` | Ownership guard: when set, the loop only picks tickets in this tracker project — protects multi-repo trackers from cross-repo picks. Empty = no guard. |
| `AZURE_TAGS` | Azure only. Tags every work item must carry (comma-separated, exact, case-insensitive) before the hub mirrors it, lists it eligible or accepts it for a run; narrows with `AZURE_AREA_PATH` / `AZURE_TEAMS`, and items Cobble files carry them. Empty = the whole team project. |
| `EPIC_ADOPT_PARENT` | `queued` (default — only a parent already in flight) \| `always` \| `never` — when a ticket queued on its own builds on its tracker parent's epic branch instead of `BASE_BRANCH`. |

"Why didn't it pick my ticket" is almost always answered here: wrong label, a missing
`PICK_LABELS` label (or `AZURE_TAGS` tag), a hold label, wrong state, a blocker relation
(`blocked_by` edges are enforced — across Projects too when both sit in one hub
Workspace, ADR 0139), another repo's `PROJECT`, triage relabelled it, or — on a
`WORKTREES=1` folder repo — no `Repo:` line (see Worktrees). A ticket that vanished from
every pull may be tombstoned: `list_deleted_tickets`.

## Loop behavior

| Key | Meaning |
| --- | --- |
| `PROVIDER` | `claude` (default, the battle-tested path) \| `codex` \| `kimi` \| `auggie` \| `copilot` \| `deepseek`. Fixed per ticket once a run starts (a live `switch_provider` aside). |
| `DELIVERY` | `automerge` (default) \| `stop` — how a green PR ships (ADR 0268). `automerge` merges on green CI; a forge that requires a review holds the PR in process for that verdict. `stop` holds the run at the PR after green CI — row `awaiting-qa`, run exits, lane freed, worktree and app stay up for QA — until **Approve** (`approve_qa`, merges with `MERGE_METHOD`), **Reject** with notes (`reject_qa`, a fix round), a trusted comment / changes requested (parks `awaiting-changes`; an armed drain answers it) or a **merge on the forge** (settles done). A forge approval alone ends nothing. Reject and comment rounds share `MAX_REVIEW_ROUNDS`. An epic holds once, at its release PR, never per child; a Folder epic that declares no child holds at each sub-issue's child PRs in turn. The verify-gate holds (`browser_not_driven`, `input_not_supplied`) apply **under `stop` only**; under `automerge` the run continues and records a notice (ADR 0345). A queued item's `delivery` (`automerge` \| `stop` \| empty = follow repo) overrides it for that run alone. Merge-affecting. Replaces the retired `AUTO_MERGE`, `REVIEW_GATE` and `QA_GATE` (and the `qa_gate` override, `--qa-gate`, `--skip review\|merge`). |
| `MERGE_METHOD` | `squash` (default) \| `merge` \| `rebase` — how green PRs land, and what Approve uses under `DELIVERY=stop`. `DETERMINISTIC_COMMIT=1` (default) writes a templated Conventional Commit on squash repos. |
| `EPIC_STACKED_PRS` | `0` (default). `1` = experimental native GitHub stack instead of an epic branch; upper layers defer CI to the stack merge. Epic flow itself is the only flow — `EPIC_FLOW` is retired (ADR 0300): a ticket with sub-issues always runs as an epic. |
| `CONFORMANCE` | `1` (default). After an epic is set done, one conformance pass drives the browser on the merged base in its own lane (needs `WORKTREES=1`, else a skipped result) and grades it against the decision-board picks, the Interview's clarifications and `## Epic acceptance criteria`. Never blocks the epic or changes its status; a deviation notifies. Route: `<PROVIDER>_CONFORMANCE_MODEL` / `_EFFORT`. Re-run with `trau --reverify <ID>` / `reverify_run`. |
| `REQUIRE_CI` | `auto` (default) = gate merges on CI when the repo's own GitHub Actions or Bitbucket Pipelines configuration answers a pull request into the PR's base; a repo with no pull-request pipeline waits one `CI_TIMEOUT` and then merges with a warning (one whose pipelines target other branches merges after a short grace). `1` insists on checks (absent ones time the run out — set `0` on a push-only repo instead). A red check fails the gate; a **pending** check never quarantines — it waits up to `CI_PENDING_TIMEOUT` and then pauses the run (ADR 0274); unreadable checks pause too. Merge-affecting. |
| `CI_TIMEOUT` / `CI_POLL` / `CI_PENDING_TIMEOUT` / `EXPECTED_CHECKS` | `600` s to wait for checks to appear and settle, `30` s poll, `3600` s more once a check is seen and still running (then a resumable pause), which checks to insist on. |
| `MAX_REPAIRS` / `MAX_BUGFIXES` | Repair attempts default `2`. **Bugfix attempts default to unlimited** (empty or `0`): a default-config run keeps bugfixing until verify passes or a budget cap stops it, and only an explicit `N` makes verify give up and quarantine. A repeated identical verify failure pauses the run instead (ADR 0311). |
| `MAX_ITERATIONS` | Tickets per run; default unlimited (`--max 0`). An epic child loop that hits a cap with open children left reports `capped` and re-queues — not a quarantine. |
| `MAX_REVIEW_ROUNDS` | `10` — fix rounds spent answering a PR's review feedback (fix or decline each thread, reply, re-request review) **and** `DELIVERY=stop` Rejects, together. The round past it quarantines the run `needs-human` before any agent runs. |
| `REVIEW_RESOLVE` | `reviewer` (default) \| `trau` — who closes a thread trau fixed: reply and leave it open for the reviewer, or resolve it. Declined threads stay open either way. |
| `TRUSTED_REVIEWERS` | Comma-separated forge identities (GitHub login, GitLab username, Bitbucket `account_id` or `{uuid}`, Azure DevOps sign-in email) whose feedback trau acts on regardless of forge permissions — rung 1 of the trust ladder (ADR 0064). Feedback from an author no rung can vouch for **parks** the PR until someone is added here or decides on it; the sweep keeps reading it, so adding the author resumes it. |
| `ADR_POLICY` / `ADR_DIR` | `1` / `docs/adr`. Interviews, planning, build and every repair path consult the repo's ADRs and record new durable decisions; cold verify must return a structured ADR result (`recorded` \| `followed` \| `none` \| `missing` \| `conflict` \| `unwarranted`) and **fails the verdict** on a missing ADR, a missing/malformed result or an ADR recording a routine choice, whatever `VERIFY_CHECKS` or `VERIFY_EFFORT` say. A diff contradicting an accepted ADR the issue does not authorize **pauses** the run (`ADR conflict needs human input: …`) until a person settles it with `settle_adr_conflict` / `trau adr authorize\|keep` — editing the issue does not clear it. `ADR_DIR` must stay inside the repo; a bad one pauses the run (`ADR policy cannot run: …`). `0` drops the instructions and the gate. |
| `DOCS_POLICY` / `DOCS_POLICY_NOTE` | `1` / empty (ADR 0287). A documentation block in Interview, build, bugfix, repair and cold-verify prompts: repo docs describe current behaviour and are never a log. Verify adds a `[docs]` failure and fails the verdict when the diff appends a run report / status entry / dated note nobody asked for, or leaves a doc the change made wrong. The note (≤ 2000 bytes) adds the repo's own rules beneath; it never removes the built-in ones. `0` drops block and failure. |
| `OUTPUT_LANGUAGE` | `English` (default) or one of 15 others (`describe` lists them). The language of human-facing agent text — Interview / Assistant questions and new tickets, hub answers, handoff and build notes, verify report, How to test, distilled lessons. Code, keys, commands, parsed JSON and sentinel lines stay verbatim; PR summary, commit messages, review replies and Publish stay English. The project layer wins over the user layer. |
| `COMMIT_TEMPLATE` / `PR_TITLE_TEMPLATE` / `BRANCH_TEMPLATE` | Full-control message and name formats; empty = trau's own (`{{.Type}}: {{.Subject}}` + `Refs: {{.Ticket}}`; `feature/{{.Ticket}}-{{.Slug}}`). `{{.Ticket}}` is the origin key when set, else the id. A `BRANCH_TEMPLATE` without `{{.Ticket}}` or `{{.ID}}` refuses the config load, and so does any template naming an unknown placeholder. |
| `PR_BODY_TEMPLATE_FILE` | Path (relative to the PR's repo root) to a Markdown `text/template` for PR bodies. A missing, empty or unrenderable file **fails the run** — there is no fallback to the built-in body. |
| `CLAUDE_DISALLOWED_TOOLS` | `Agent,Workflow,Bash(git push:*),Bash(gh pr create:*)` — delivery commands blocked in every claude phase (the loop delivers, not the agent). Per-phase `CLAUDE_<PHASE>_DISALLOWED_TOOLS`. When a Laravel Herd MCP server is configured, its site-changing tools are appended to every phase's list and no override re-enables them. Codex/Kimi/Auggie have no deny list; the prohibition is prompt-only there. |

The pick gate and `PICK_ROUNDS` no longer exist (ADR 0059).

## Lessons and calibration

| Key | Meaning |
| --- | --- |
| `LESSONS_DISTILL` | `1` (default). After a verify that passed only after a repair, or a quarantine, one cheap pass distills the lesson (≤ 240-char takeaway, failure class slug, touched paths) on `<PROVIDER>_DISTILL_MODEL` / `_EFFORT`. Outside the run's budget; never changes the outcome. `LESSONS` itself (default `1`) is read at runtime but sits outside the catalog. |
| `TEAM_SYNC` | `0` (default; not shareable). **Opt-in lesson sharing over the repo's own git remote** (ADR 0283): on, the hub publishes this hub's lessons (secrets masked) to `refs/trau/lessons/<install-id>`, fetches teammates' refs and merges them into `list_lessons` and recall. Setting it on runs one full sync first and is refused, with the remote's reason, when the publish fails, the repo is a Folder repo or has no remote. Off removes every teammate lesson and deletes this hub's ref. The key reuses the retired team-sync name, so a stale `TEAM_SYNC=1` in a file or the environment counts as on. |
| `CALIBRATION_AUTO_APPLY` | `0` (default). **Hub-wide.** Lets the daily calibration sweep apply, by itself, a proposal that only *lowers* a cost knob (`MAX_REPAIRS` / `MAX_BUGFIXES` down, or one build / handoff / repair / bugfix / cleanup / lintfix / commit effort step down), then watches the next 20 runs and reverts on a quality drop (ADR 0329, 0336). Band limits, Presets, Models, `TEST_EFFORT` and every step up still wait for the operator (`list_calibration_proposals`, `decide_calibration_proposal`, `calibration_report`); it never touches `VERIFY_EFFORT`, a verify Route, a cost cap, a credential or a delivery key. |

A recurring lesson class becomes a rule proposal (ADR 0335): `list_lesson_promotions`,
`apply_lesson_promotion`, `dismiss_lesson_promotion` — no key.

## AI assessment and models by complexity

| Key | Meaning |
| --- | --- |
| `AI_ASSESSMENT` | `0` (default). **Hub-wide**, user layer or hub environment only, needs an active license key. The one consent for the Cobble assessment service: Complexity scores and readiness signals, lesson classification and recall, skill relevance, grill question checks, duplicate, split and Complexity checks of proposed tickets, repair-stall checks. On, the hub sends ticket titles, descriptions and comments with their sub-issues, each ticket's Declared facts, verify failure evidence, recalled lessons, package and skill signals, grill questions, proposed tickets beside existing ones, and each Interview proposal's hierarchy and restatement (the service does not retain them). No pick or Queue decision reads an answer; a run reads the score only through `MODELS_BY_COMPLEXITY`. The retired per-feature assessment keys do nothing. |
| `MODELS_BY_COMPLEXITY` | `0` (default, per repo, needs `AI_ASSESSMENT` and a licence). A ticket with a usable Complexity score runs under the saved Preset its Provider maps to its band — `<PROVIDER>_COMPLEXITY_LOW_PRESET` / `_MEDIUM_PRESET` / `_HIGH_PRESET`, looked up among that Provider's Presets (the run's Provider and each fallback read their own keys). The unprefixed `COMPLEXITY_*_PRESET` keys are retired. The band is fixed at ticket start; no score, no mapping or no such Preset keeps the configured Routes. Ticket text never names a Model. A hub write that turns it on seeds missing `Complexity low` / `medium` / `high` Presets for claude and codex, and `DeepSeek Flash` / `DeepSeek V4 Pro` for deepseek, into empty band keys. Run log: `complexity 7 -> band high -> Preset "deep"`. |
| `COMPLEXITY_LOW_MAX` / `COMPLEXITY_HIGH_MIN` | `5` / `8` — band limits on the 1–10 score; an invalid pair falls back to 5 and 8 with a warning. |
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
bill to the same ledger (the distill pass does not count against a run's budget). On a
worktree repo, where every eligible ticket can run at once, these caps are the *only*
throughput throttle. And **the USD caps never fire on auggie or copilot** (they report
tokens and credits, no `cost_usd`; kimi has no price either) — set the token caps there.

With `MAX_BUGFIXES` unlimited by default, the budget caps are also what bounds a run
that keeps failing verify. A run that stopped "for no reason" may simply have hit
one; `trau forensics spend <ID>`, `get_costs` and `trau --status` show the numbers.

## Verify

| Key | Meaning |
| --- | --- |
| `VERIFY_CHECKS` | `1` (default) runs the pluggable check library — repo-defined checks in `<repo>/.trau/checks/*.yaml`, or a built-in set (tests, typecheck, lint, anti-placeholder, anti-duplication). `error` severity blocks the merge. |
| `BROWSER_VERIFY` | `auto` (default — a UI slice should be driven; one that passed with no browser driven holds `awaiting-qa` / `browser_not_driven` under `DELIVERY=stop`, and continues with a notice under `automerge`; with no reachable app the skip is a note) \| `always` (an undriven UI slice is re-verified once and then **pauses** `browser_verify`, as does a missing, malformed or unanswering `APP_URL`) \| `never`. A backend-only slice is not-applicable at every level. |
| `BROWSER_ISOLATION` | `managed` (default): build always gets a dedicated headless browser, verify / repair / bugfix when the slice has a UI surface, and every other phase has the shared-browser env (`BU_CDP_*`, `BU_NAME`) stripped so no agent drives the user's browser. `attach` is the old shared-browser behaviour. Why no window opens and why two lanes never share tabs. |
| `BROWSER_HARNESSES` | `agent-browser,browser-harness` (default) — ordered managed harnesses; the first is primary, later ones are startup fallbacks, a single entry disables fallback. A phase left with no harness runs with **no browser** rather than falling back to yours. `trau browser setup` provisions both, `trau browser status` reports readiness. The single-value `BROWSER_HARNESS` is retired. Missing OS libraries pause the run `tool_unavailable` with the fix `trau browser setup --system` — which installs OS packages and needs a person at that machine; never auto-resumed. |
| `APP_URL` / `APP_URLS` | Fallback only: the hub's stored app URL entries (ADR 0026) replace both wholesale, and the hub saves an answering detected URL as an entry itself at registration, hub start and run start (`trau app-urls detect`, `app_urls_detect`). `APP_URLS` maps monorepo package workspaces to URLs. |
| `VERIFY_PANEL` / `VERIFY_PANEL_POLICY` | Cross-vendor verify: N isolated verifiers from different providers, merged `unanimous` (default) \| `majority` \| `any-pass`. |
| `VERIFY_EFFORT` | `high` \| `medium` (default) \| `low` — how strictly verify grades a slice. It narrows **both** what the verifier investigates and what can fail the verdict, so a lower level is cheaper and faster, not just more lenient: `high` is full adversarial QA, `medium` the rubric plus regressions in what the slice touched, `low` the rubric contract alone; at low and medium an issue outside the brief is a non-blocking note. The mechanical test gate runs at every level. There is no `off` value (skipping verify is a per-run skip). Not the same knob as `CLAUDE_VERIFY_EFFORT` / `CODEX_VERIFY_EFFORT`, which set the *provider's* reasoning effort for the phase. |
| `TEST_EFFORT` | `low` (default) \| `off` \| `medium` \| `high` — how much test work build is asked for (ADR 0041). |
| `VERIFY_PROOFS` / `PROOF_RETENTION_DAYS` | `on` / `14`. Browser verify saves key **screenshots** only (video and traces were removed, ADR 0089). Destination: `attachments` (GitHub, `gh` ≥ 2.99 — PR attachments, never pruned; a rejected upload retries the PR once without proofs), else the `trau-proofs` branch, else `hub` (kept, no PR link). Retention applies to the `trau-proofs` branch only and is the **hub's own** value — a project-layer value is not read; `0` = forever. `trau doctor` and `GET /api/v1/repos/{repo}/proof-storage` name the destination and any fallback. |
| `QA_NOTES` | `1` (default) posts the run's QA report as a ticket comment on delivery or give-up. |
| `SERENA` / `SERENA_BACKEND` / `SERENA_INTERFACE` | `auto` (default) \| `required` \| `off` — Serena MCP readiness check before build (ADR 0057). `required` fails `trau doctor` and pauses a run until Serena is reachable. Serena stays optional: trau never installs it, and the one Serena setting it writes is the trust pattern, only on `trau serena trust` (ADR 0301). Backend `auto` \| `LSP` \| `JetBrains`. Interface `tools` (default) \| `REPL` (Serena v2's single `serena_repl` tool, beta) for claude and copilot spawns. On auggie/kimi the registration check is marked *skipped*, never failed. |
| `BENCHMARK` | `off` \| `suggest` (default) — the Interview writes a `## Performance budget` only when the user asks; build measures and verify vets only a ticket that has one. Measurements via `get_artifact kind=benchmark`. |

## Worktrees and parallelism

| Key | Meaning |
| --- | --- |
| `WORKTREES` | `0` = one checkout, serial drain. `1` (default) = each queued run gets its own worktree, branch, and PR — and **every eligible queued ticket runs at once**, with no lane cap (ADR 0047). On a **folder repo** it means: a ticket whose description opens with `Repo: <child>[, <child>…]` runs in a lane holding one linked worktree per declared child, isolated lanes are unlimited too, and a ready ticket with **no** `Repo:` line is refused before any agent call. |
| `WORKTREES_DIR` | Where the trees live: `<WORKTREES_DIR>/<repo-name>/<ticket-id>` (folder lanes add `/<child>`); defaults to `<TRAU_HOME>/worktrees` (`TRAU_HOME` itself defaults to `~/.trau`). It must not sit inside a registered repo. |
| `WORKTREE_COPY` | `.env,.env.*` — gitignored globs copied into a fresh tree (on top of the unconditional set: `.trau/`, `.gitconfig.repo`, a folder child's `.trau.ini`, untracked `.agents/`, `.serena/` project + memories, the `.claude/skills` mirror). Replaced by `worktree.yaml` `copy:` when present. |
| `WORKTREE_SETUP_CMD` | Runs in each fresh tree (e.g. `npm ci`) under the host shell, with `TRAU_TICKET` (and `TRAU_APP_URL` / `TRAU_APP_HOST` / `TRAU_APP_BASE_HOST` in Herd mode). Replaced by `worktree.yaml` `setup:` when present. Caches and search indexes the trees would share are still this command's to separate; **ports and the database are not** — the hub allocates ports and copies the database before it runs. A non-zero exit parks the run faulted with its output kept as a `worktree-setup` artifact and the tree left standing as evidence. Folder lanes resolve it per child. |
| `WORKTREE_DB` / `WORKTREE_DB_URL` | `auto` (default): every lane gets **its own copy of the checkout's dev database** (MySQL/MariaDB/PostgreSQL/SQLite, `docker exec` fallback), named `<source>_<ticket>[_<child>]`, dropped on settle, with the tree's `.env` repointed and `TRAU_DB_*` exported to setup/start commands (ADR 0070). `on` faults instead of sharing when no source is found; `off` copies nothing. A failed copy parks the run faulted with a `worktree-database` artifact. `WORKTREE_DB_URL` is the admin connection URL — a secret. |
| `WORKTREE_DB_CONTENT` / `WORKTREE_DB_WARN_SIZE` | `full` (default — schema and every row) \| `schema` (structure only; setup must then migrate and seed). An existing lane database keeps the content it was made with. Warn size `1G` (`0` = off): a larger source is flagged in the run log, Worktrees → Setup and `trau worktree test-setup`, naming `schema` and `WORKTREE_DB=off`; the copy still runs in full. |
| `SUPABASE_LANE` / `_EAGER` / `_EXCLUDE` | `auto` (default — a `WORKTREES=1` repo whose root holds `supabase/config.toml` gets one local Supabase CLI stack per lane before setup) \| `local` (same, and a root without the file faults the run) \| `off` (ADR 0343). The hub holds nine ports per lane, rewrites copied `.env*` values of the developer's own local stack to the lane's, exports `TRAU_SUPABASE_*`, and destroys the stack with its data on settle. A stack that cannot start (no Docker, no CLI ≥ 2.119.0) faults the run with a `worktree-supabase` artifact. `_EAGER` `0`; `_EXCLUDE` `studio,analytics`. Folder repos get none yet. |
| `APP_SERVE` | `auto` (default) \| `herd-workspace` \| `herd` \| `command` \| `off` — how a tree's app is served. `auto` picks Herd when the `herd` CLI is on PATH, the repo is one of its sites *and* `APP_START_CMD` is empty — `herd-workspace` when that CLI has the Herd 2.0 `workspace` command (the tree answers at `<branch>.<site>.test`), `herd` (a link per tree, `http(s)://<ticket>.test`, **no port**) otherwise; the command when it is set; nothing when neither holds. An explicit `herd` / `herd-workspace` on a CLI that cannot do it fails the start rather than falling back. With `WORKTREES=0` the same modes decide the *checkout's own* server: `command` probes the configured app URL, adopts a dev server that already answers, and starts the command only when nothing does; trau stops only servers it started. Replaced by `worktree.yaml` `app:` when present. |
| `WORKTREE_HOSTS` / `APP_HOSTS` | `auto` (default) \| `off` — under `APP_SERVE=herd`, a saved app URL on the checkout's Herd base host maps onto the lane (`http://app.salonradar.test` → `http://app.<ticket>.test`) and the copied `.env` follows; `off` leaves the `.env` alone. `APP_HOSTS` (empty) names secondary hosts as `<ENV_KEY>=<label>` pairs (`ADMIN_URL=ops`) that each lane rewrites, serves and tells browser verify about. |
| `APP_START_CMD` | Serves the app from inside a worktree on a hub-allocated port (`$PORT` / `$TRAU_APP_PORT`), so browser verify tests the branch under test. Governed by `APP_SERVE`; empty leaves the browser gate on the stored app URL entries. Readiness wait 60 s; a command that never listens is marked failed and the run continues on the advisory no-URL path. |
| `WORKTREE_PORT_BASE` | Lowest port a worktree app may be given (default `4300`); each tree takes the lowest free port at or above it, within a 200-port window. Folder lanes reserve one port per serving child up front; Supabase lanes take nine more. |

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
| `SERVE_TOKEN` | Required the moment the bind leaves loopback, and in hosted mode — the hub refuses to start exposed without it; all requests then need `Authorization: Bearer`. Editable from Settings; read at serve start. |
| `SERVE_PUBLIC_URL` / `SERVE_TRUSTED_PROXIES` | Empty (default) = not hosted. Set to the public origin behind a reverse proxy (e.g. a Cloudflare Tunnel to the loopback bind) and the hub is in **hosted mode**: same-origin checks use it, `SERVE_TOKEN` is mandatory, and every forwarded request needs a collaborator session (`trau collaborators add`) or the operator token (ADR 0249). Trusted proxies (CIDRs; loopback always trusted) decide which `X-Forwarded-For` hop the sign-in rate limit counts. Both read at serve start. `trau hosted setup\|status\|deploy` provisions such an environment. |
| `HOSTED_REPO_REFRESH` | **Hub-wide**; on in hosted mode, off otherwise. Every 15 min a bounded fetch and a fast-forward of each clean checkout sitting on its base, so Interviews read remote changes; never pushes, resets, stashes or switches branch — a checkout that is off base, dirty or held is reported incomplete. `repository_refresh_status`, `retry_repository_refresh`. |
| `SERVE_ALLOW_REGISTER` | `0` (default): on an exposed hub, (un)registering repos, `add_project_repo`, project CRUD, filesystem browse/discover and other widen-the-footprint routes are refused even with the token — a leaked token can't widen where agents run. |
| `SERVE_WORKSPACE` | An extra **startable** allowlist. The hub may start (and stop) loops in the repos **Registered** with it plus whatever this key lists; a repo it merely discovered stays observe-only for both start and stop (`403 repo is observe-only`). Empty — the default — means Registered repos only. It is not a list of the repos the hub serves, and it has nothing to do with hub-UI **Workspaces** (ADR 0073 — a per-browser grouping of Projects with no config key) or `APP_URLS`' *package workspaces*. |
| `SERVE_REMOTE` | `off` (default) \| `tailscale` — publish the hub on the tailnet's HTTPS port, bind still loopback, no port opened to the internet. `trau hub remote on\|off` writes this key; the hub reconciles the forward against it at start and about once a minute after. |
| `HUB_PEER_URL` / `HUB_PEER_TOKEN` / `HUB_PEER_ID` | Runner presence. Empty (default) = no outbound request. Set `HUB_PEER_URL` (a central hub's base URL) and this hub heartbeats to it at start and every 30 s: host, version, its off-machine URL, and per registered repo the draining state, live lanes and last tracker sync — no ticket text, code or credentials. `HUB_PEER_TOKEN` (a secret) is the bearer the heartbeat presents — needed when the central hub binds off loopback with a `SERVE_TOKEN`; `HUB_PEER_ID` is minted on the first heartbeat — changing it lists the machine twice. |
| `SERVE_AUTOSTART` | `1` (default): the first interactive `trau` session brings the hub up first. `--no-serve` disables it for one run. |
| `SERVE_OPEN` | `1` (default): a fresh hub spawn (and `trau hub start`) opens the browser. |
| `SECRET_REVEAL` | `off` (default) \| `admin` — arms the audited one-secret-per-call reveal path (`reveal_secret`, `--reveal`). Until a repo sets it, the tool is absent from the hub's `tools/list`. |
| `TICKET_SECRETS_KEY` / `ACCOUNT_SECRETS_KEY` | Not settable here: read only from `TRAU_TICKET_SECRETS_KEY` / `TRAU_ACCOUNT_SECRETS_KEY` at serve start (base64 of 32 random bytes). The first seals ticket secrets, terminal passwords and service-connection tokens (ADR 0275) — absent, the hub creates `keys/ticket-secrets.key` under the trau home once; the second seals collaborators' personal API keys and tracker credentials (`trau hosted setup` mints it). A missing or wrong key means nothing sealed opens and nothing falls back to plaintext. Back the key up with the database; never set or rotate one yourself — relay the `reason` to the user. |
| `HUB_SELF_RELOAD` | `0` (default). `1` lets **the trau source checkout** rebuild and restart the hub from Settings → Updates — `HUB_RELOAD_BUILD_CMD` (default `make build`), `HUB_DEV_BINARY` (default `bin/trau`), `HUB_RELOAD_PULL` (fast-forward first). Shipping a ticket never rebuilds the hub. Any other repo is refused and never sees these keys. |
| `QUEUE_AUTO_DRAIN` | `0` (default). **Standing drain**: `1` keeps this repo's drain armed after the queue runs dry, and every issue sync (`SERVE_SYNC_INTERVAL`, 120 s) enqueues the unblocked leaf tickets carrying `READY_LABEL` and starts them — no one presses Start, and it arms with `on_fault=skip`. It spends tokens with nobody watching; set it only when the user asks. An armed, empty standing drain reads `held_gate: idle`. |
| `QUEUE_AUTO_RESUME` / `QUEUE_AUTO_RESUME_TRIES` | `0` / `2`. With auto-resume on, the hub re-attempts an item whose run **paused** (a provider wall, an unreachable hub, a dialog, …) once a backoff passes — 2 minutes × attempt — and gives up after N tries. Never a fault, a stop, a `held` row, an **ADR-conflict** pause or a pause waiting on `trau browser setup --system`. The plan lives in the hub's memory, so a hub restart forgets it and the item stays parked. A crashed epic release gets two tries regardless. |
| `HOOK_GENERIC_SECRET` / `HOOK_SENTRY_SECRET` / `HOOK_NIGHTWATCH_SECRET` | Webhook intake, per repo; empty (default) = the route answers 404. Each secret (HMAC-SHA256 of the raw body; a mismatch is 401) enables `POST /api/v1/repos/<repo>/hooks/{generic,sentry,nightwatch}`. An *opened* event **files an internal bug ticket** labelled `READY_LABEL` + `bug` + the source, **queues it and arms the drain** (`on_fault=skip`); a repeat open comments, *reopened* re-queues an idle ticket, *resolved* dequeues and cancels it unless a run holds it. With `SENTRY_API_TOKEN` set, a sentry-hook ticket is enriched with the latest event's stack trace. |
| `SENTRY_API_TOKEN` / `SENTRY_ORG` / `SENTRY_PROJECTS` / `SENTRY_BASE_URL` | The **Sentry Monitoring source** (ADR 0278, 0284), connected on the Monitoring page once token, org slug and project slugs are saved; it polls new issues (first seen after connecting) into Draft Interviews. Token (a secret) needs `event:read`, `event:write`, `project:read`, `org:read`. A project slug belongs to one repo per org. Base URL default `https://sentry.io` (self-hosted or region host). |
| `SENTRY_MODE` / `SENTRY_QUERY` / `SENTRY_POLL_INTERVAL` / `SENTRY_RESOLVE_AFTER` | Mode `draft` (default — the item waits on Monitoring for the user to start or dismiss) \| `auto` (the hub runs the Interview with auto-accept, approves a create as Operator, files, queues and arms the drain — the one unattended write approval; set only when the user asks; anything else waits on Prepare with a `monitor_attention` notification). Query default `is:unresolved`; poll `5m` (≥ `1m`); resolve-after `24h` \| `off` — a merged fix's issue quiet that long is resolved in Sentry, and one Sentry reopens returns marked Regressed. |
| `UPDATE_CHECK` / `AUTO_UPDATE` / `TRAU_LICENSE_KEY` | `1` / `1` / empty. Daily check of `get.trau.sh` for a newer release — no key needed (ADR 0106). With `AUTO_UPDATE` on (release channel, not hosted), the hub installs a newer release itself and restarts at the next ticket boundary — an armed drain holds `held: restarting onto vY` meanwhile. **Update lock** (ADR 0322): a release-channel hub refuses new agent work (`update_required`, drain held on the `update` gate, still armed) once a newer release has been known for 8 wall-clock hours, until it runs it; in-flight runs finish. `UPDATE_CHECK=0` is the only bypass. The license key (a secret, hidden from Settings) is what the account profile sends; `trau license set` reads it from stdin. |
| `SKILL_UPDATE_CHECK` | `1` — once a day, compare the globally installed operator skill (`RomkaLTU/skills@trau`) with upstream and offer the update in Settings. Reads the skills.sh lock of the hub's OS user, never writes it, installs nothing on its own; needs no license. |
| `CRASH_REPORTS` | `1` (default): a panic or pipeline fault sends one crash event to trau's Sentry (ADR 0057). `0` or `DO_NOT_TRACK=1` disables; `trau doctor` *crash reports* states which. Unrelated to the manual, unredacted `trau dump`. |
| `NOTIFY` / `HOLD_REMINDER_HOURS` | `0` / `24`. `NOTIFY=1` fires a native desktop notification for every bell item — paused / faulted / quarantined runs, PRs awaiting merge or QA, changes requested, hold reminders, an epic parked or delivered, a conformance deviation, interview questions, a finished publish. Rows sitting on a human (`awaiting-merge`, `awaiting-changes`, `awaiting-qa`, `no-change`) are re-notified every `HOLD_REMINDER_HOURS` (0 = once). A reminder never moves a row. |
| `USAGE_WINDOW` / `THEME_MODE` | `1` — show the active provider's real rate-limit window in the usage HUD (Claude's comes from trau's own Claude sessions' status line; trau never reads a sign-in token). `dark` (default) \| `light` — the hub-wide mode the web UI's toggle writes; runs pick provider colours from it. One web layout (`WEB_LAYOUT` retired, ADR 0348). |
| `ARTIFACT_PUBLIC_SHARE` | `0` (default). **Hub-wide.** `1` lets the operator share an Interview artifact with "Anyone with the link" at `/shared/<token>`, no session; off makes every artifact Members only and kills existing links. |
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
`trau tools install [claude] [codex] [gh]` installs missing CLIs into `~/.local/bin`
and seeds their config so no run stops on a first-run dialog (ADR 0302).

**DeepSeek** (`PROVIDER=deepseek`, ADR 0347) has no CLI of its own: `DEEPSEEK_MODE`
`claude` (default — Claude Code against DeepSeek's Anthropic-compatible endpoint;
Anthropic does not support that routing) \| `codex` (Codex CLI with `--profile trau`
under a seeded DeepSeek model provider). `DEEPSEEK_BIN` follows the mode (`claude`);
`DEEPSEEK_FLAGS` defaults like `CLAUDE_FLAGS`; `DEEPSEEK_MODEL` default
`deepseek-flash[1m]` (`deepseek-v4-pro` for heavy routes). `DEEPSEEK_API_KEY` is not a
catalog key — it is read from the **hub's environment**, and `trau doctor` flags it
missing.

`<PROVIDER>_<PHASE>_MODEL` / `_EFFORT` route each phase — `BUILD`, `HANDOFF`,
`VERIFY`, `REPAIR`, `BUGFIX`, `CLEANUP`, `COMMIT`, `PICK`, `PROOFREAD`,
`CHECKLIST_CHECK`, `CHECKLIST_DO`, and the passes `CONFORMANCE` (epic conformance),
`DISTILL` (lessons distill) and `TASK_ORDER` (the Backlog's Suggested order, a
tool-less pass); `GRILL` for non-claude providers. Kimi and Auggie take `_MODEL` only.
Claude phases also take `CLAUDE_<PHASE>_DISALLOWED_TOOLS` / `_OUTPUT_STYLE` /
`_COMPACT_WINDOW`. The **Models** page (Models by phase, Models by complexity) and its
Presets edit these. The `*_LINTFIX_*` route keys are retired: the lint-fix phase runs
`LINT_FIX_CMD` only, no agent. `FALLBACK_PROVIDERS` lists ordered
`provider[:model[:effort]]` specs to try after the primary's retries are exhausted
(empty = retry only).

Tracker credentials: `LINEAR_API_KEY` (enables fast direct GraphQL alongside MCP),
`JIRA_BASE_URL` / `JIRA_EMAIL` / `JIRA_API_TOKEN` (a classic, unscoped token on Cloud),
`AZURE_ORG_URL` / `AZURE_PAT`. Forge credentials: a **Bitbucket Cloud** remote needs a
connection (below) or `BITBUCKET_EMAIL` + `BITBUCKET_API_TOKEN` (a scoped Atlassian
API token — app passwords were removed in July 2026) and is **refused before the run
spends anything** without one; an **Azure Repos** remote needs `AZURE_PAT` with the Code
and Build scopes (native REST, ADR 0281; Azure DevOps Server too, ADR 0338 —
`AZURE_HOSTS` lists a Server host whose remote path lacks `/_git/`); GitLab needs
`GITLAB_TOKEN` (Additional controls). A GitHub remote uses a GitHub connection or `gh
auth`. No repository-admin grant is needed for review trust — see `TRUSTED_REVIEWERS`
and the ladder in `references/operations.md` § Review feedback loop.

**Service connections** (ADR 0139–0142, 0327) are OAuth sign-ins the hub holds per
account — `trau connect linear|jira|bitbucket|github`, `trau connections [remove <id>]`,
Settings → Connections, `list_connections` / `test_connection` / `remove_connection`.
Only the user can approve the consent page, and no surface returns a token. In hosted
mode a queued ticket runs as the person who queued it, on that collaborator's personal
connections (ADR 0331).

| Key | Meaning |
| --- | --- |
| `LINEAR_CONNECTION` | Account label (or id) of the Linear connection a repo uses; empty picks the only one. A resolved connection beats `LINEAR_API_KEY`. `LINEAR_OAUTH_CLIENT_ID` ships a built-in default; empty = no Linear sign-in. |
| `JIRA_CONNECTION` | Label or id; empty picks the only one reaching `JIRA_BASE_URL`. Beats `JIRA_EMAIL` / `JIRA_API_TOKEN`; while `get.trau.sh` is unreachable it keeps its last token until that expires, then falls back to them. Sign-in goes through `get.trau.sh` (needs the license key) unless `JIRA_OAUTH_CLIENT_ID` + `JIRA_OAUTH_CLIENT_SECRET` name the operator's own Atlassian 3LO app (callback `<hub origin>/api/v1/oauth/jira/callback`). Cloud only. |
| `BITBUCKET_CONNECTION` | Label or id; empty picks the only one reaching the remote's workspace. Beats `BITBUCKET_EMAIL` / `BITBUCKET_API_TOKEN` and falls back to them when it needs a new sign-in. Requires the operator's own OAuth consumer — `BITBUCKET_OAUTH_CLIENT_ID` / `_SECRET` (`pullrequest:write`, `repository:write`, callback `<hub origin>/api/v1/oauth/bitbucket/callback`), which reaches only the workspace that created it. The same connection authenticates git over https to `bitbucket.org` via `trau git-credential` (internal — never run it). |
| `GITHUB_CONNECTION` | Login or id; empty picks the only one. Signs in through trau's GitHub App (`cobble-do`) over `get.trau.sh`, or the operator's own GitHub App when `GITHUB_OAUTH_CLIENT_ID` + `GITHUB_OAUTH_CLIENT_SECRET` are set (callback `<hub origin>/api/v1/oauth/github/callback`). Token order: an operator-set `GH_TOKEN` / `GITHUB_TOKEN`, then the connection, then the `gh` keyring; `gh` still executes every call. Settings → Connections can also run `gh auth login` and `gh auth setup-git` (writes the user's global git config — ask first). |

All of these keys live clear-text in the hub database like every other config key —
there is no "safer file" to put them in, only the database's own permissions and the
`SECRET_REVEAL` audit on the way out. (Connection tokens are the sealed exception.)

## Research, interviews and prototypes

| Key | Meaning |
| --- | --- |
| `TWG_ENABLED` / `TWG_BIN` | `0` / `twg` (per repo, Jira trackers only). Gives that repo's Research and Interview sessions two read-only Teamwork Graph reads — one related-context read and up to three document reads per session — against `JIRA_BASE_URL`. Session tools only, not hub MCP tools. Trau never installs, signs in to or updates `twg`: the user does, as the hub's OS account, with a read-only grant. Reads may use Rovo credits, and selected text reaches the AI Provider. Turn on only when the user asks. |
| `GRILL_PROVIDER` / `GRILL_MODEL` | Provider (empty = `claude`; any of the six) and model for the hub's Interview agent; a per-session picker choice overrides it. |
| `GRILL_MAX_STEPS` | `200` — tool calls one Interview or Research turn may make (`0` = no cap); at the cap the session parks naming this key, and Resume or a typed message continues it. A prototype turn has no cap unless this is set in a layer. |
| `ARTIFACTS` / `GRILL_ARTIFACTS` | `1` / `auto`. `ARTIFACTS` lets the Interview agent publish html / svg / markdown artifacts (and prototype bundles) beside the transcript; `0` removes `publish_artifact` and blocks prototypes. `GRILL_ARTIFACTS` `off` \| `auto` \| `requested` is the start-control prefill, fixed per session; `ARTIFACTS=0` forces `off`. Public links: `ARTIFACT_PUBLIC_SHARE` (The hub). |
| `PROTOTYPE_PROVIDER` / `PROTOTYPE_MODEL` | `claude` / `sonnet` — the only override for every Prototypes-page session (no picker there; ADR 0344). A provider that cannot publish a bundle artifact is refused; empty model falls back to `GRILL_MODEL`, then `CLAUDE_MODEL`. |
| `PROJECT_CREATION_RESEARCH_PROVIDER` / `_MODEL` | Provider (empty = `claude` \| `codex` \| `copilot`) and model for the creation Research a New Project runs before any repo exists; separate from `GRILL_PROVIDER`. |

## Cost and cadence

| Key | Meaning |
| --- | --- |
| `CLAUDE_PROMPT_CACHE_1H` | `hub` (default) \| `all` \| `off` — ask Claude Code for the 1-hour prompt-cache TTL. `hub` covers the hub's own sessions (interviews, challengers, publish, atlas and the like); `all` adds every claude pipeline phase; `off` strips an inherited setting. No-op on subscription auth. |
| `CLAUDE_OUTPUT_STYLE` / `CLAUDE_<PHASE>_OUTPUT_STYLE` | `Concise` (default) \| `Default` \| empty — prose volume of every claude spawn; empty passes no style (the escape hatch for a repo's custom style). Per phase, empty = inherit. |
| `CLAUDE_<PHASE>_COMPACT_WINDOW` | Per-phase auto-compact window in tokens (100000–1000000) for claude phases. Unset (the default) leaves Claude Code's own behaviour. Codex, Kimi and Auggie ignore them. Re-read before each agent call (ADR 0069). |
| `AGENT_TIMEOUT` / `AGENT_STALL_WINDOW` / `AGENT_RETRIES` | `3600` s per agent call, `180` s with no output before a stall is declared, `2` retries. |

File-based team sharing through `.trau/config.team.ini` and its drift checks sits
beside the git-ref lesson sharing of `TEAM_SYNC` (see Lessons and calibration); the
two are independent.

## Ticket comments

`DELIVERY_COMMENTS`, `QUARANTINE_COMMENTS` and `RESET_COMMENTS` (all `1` by default)
control the ride-along notes trau leaves on a ticket at delivery, at quarantine and
at reset. Turning one off silences the note only — the status move and the label
swap still happen.

## Additional controls in the current binary

Use `trau config describe <KEY> [--json]` for current defaults, valid options and the
full contract. Phase Models and efforts change across releases; do not copy an old
Model default into a new repo.

| Key | Meaning |
| --- | --- |
| `COPILOT_BIN` / `COPILOT_FLAGS` / `COPILOT_MODE` | GitHub Copilot CLI Provider. Mode `print` (default) is headless and takes steer notes at the next spawn; `pty` permits mid-phase steering. Flags default to `--allow-all`, which removes tool, path and URL approval prompts. A copilot child never gets the GitHub connection's `GH_TOKEN`. |
| `COPILOT_MODEL` / `COPILOT_<PHASE>_MODEL` / `_EFFORT` | Empty Model resolves to `auto`; explicit Model IDs are accepted. Per-phase Routes override the Provider Model. |
| `COPILOT_MAX_AI_CREDITS` | Per-call AI credit cap; empty or `0` = no cap, and a value under `30` runs as `30`. Copilot reports premium requests and AI credits, never USD; USD caps do not constrain it. |
| `ALLOWED_PROVIDERS` | Provider lock from the signed license entitlement (ADR 0222). `TRAU_ALLOWED_PROVIDERS` and `--allowed-providers` (on `trau serve` or a run) can narrow it only. A stored config value is ignored; a change needs a hub restart. A denied Provider pauses `provider_locked`. |
| `REQUIRE_PROVIDER_LOGIN` | Strict mode of the always-on login gate, licence-carried; `TRAU_REQUIRE_PROVIDER_LOGIN=1` can only turn it on. A stored value is ignored. A provider not installed or not signed in pauses `login_required`; strict mode also refuses when the probe fails. Sign in before resuming. |
| `<PROVIDER>_COMPLEXITY_<LOW\|MEDIUM\|HIGH>_PRESET` | Each Provider owns its mapping from Complexity band to a Preset. Use that Provider's Preset names. |
| `JIRA_DEPLOYMENT` | `cloud` (default) / `datacenter`. Data Center uses a personal access token in `JIRA_API_TOKEN` and `JIRA_BASE_URL` over REST v2; no email, no OAuth connection, no MCP fallback. |
| `GITLAB_TOKEN` / `GITLAB_HOSTS` | Secret token (`api` + `write_repository`, GitLab ≥ 16.0) for GitLab delivery — user layer, or a Project's layer to override; unset, a GitLab remote is refused before spending. A self-hosted host must be listed in `GITLAB_HOSTS` or declared with child `FORGE=gitlab`. No GitLab connection; trau never uses GitLab auto-merge. |
| `TLS_CA_FILE` / `TLS_INSECURE_SKIP_VERIFY` | User-layer PEM CA file for self-hosted forge/tracker TLS. Skip verification (`1`) is a stopgap and produces a doctor warning on every run. |

A Folder child's own `BASE_BRANCH` wins. Next comes the Folder's explicitly set base
when the child remote publishes it, then the remote default, then the Folder base.
If the remote cannot answer, the explicitly set Folder base stands. `get_run` records
`base_branch`, `remote_default_branch` and per-child `ships` for delivery diagnosis.
