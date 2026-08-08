# Configuration — what an operator needs to know

Trau's own `trau.ini.example` (shipped with the binary and in the repo) documents
every knob exhaustively. This reference covers the layering model and the knobs that
answer operator questions — "why didn't it pick my ticket", "why is the drain
serial", "why did it stop at the PR". Don't hand-write a repo's `.trau.ini` from
scratch; the onboarding wizard (first interactive `trau` run in the repo) generates
it.

## Layering

From lowest to highest precedence:

1. built-in defaults
2. `~/.trau.ini` — personal / machine baseline (provider flags, machine-trust knobs)
3. `./trau.ini` — local fallback when no target repo is given
4. `<repo>/.trau.ini` — repo-specific facts; always beats the home baseline, so a
   global credential can never shadow a repo's own
5. environment variables — any key below, or its collision-safe `TRAU_<KEY>` alias
   (`TRAU_PROVIDER` beats a generic `PROVIDER` in the shell)
6. CLI flags (`--repo`, `--provider`, …)

Keys ARE the environment-variable names — `PROVIDER=` in the file and
`TRAU_PROVIDER` in the shell are the same knob. Format is a flat INI subset
(`KEY=value`, `#` comments).

## Tracker and eligibility

What decides whether the picker sees a ticket at all:

| Key | Meaning |
| --- | --- |
| `TRACKER_PROVIDER` | `linear` \| `jira` \| `azure` \| `github` \| `internal` (trau's own hub-store issues — the automatic fallback when no external tracker is configured). |
| `LINEAR_TEAM` | Team name / Jira project key / Azure team project / GitHub repo slug. |
| `ISSUE_PREFIX` | Ticket-id prefix (`COD`, `ENG`, …) for parsing and branch inference. |
| `READY_LABEL` | Default `ready-for-agent` — what makes a ticket eligible to pick. |
| `QUARANTINE_LABEL` | Default `needs-human` — where failed tickets land; also the label to file human-attention tickets under. |
| `QUEUED_LABEL` | Default `queued` — mirrored onto tickets waiting in the hub queue; the hub heals drift on every sync. Set it **empty per machine** when several people's hubs share one tracker, or the hubs will fight over the label. |
| `SPLIT_LABEL` | Default `needs-split` — applied by the pre-flight size judge to tickets too large for one run. |
| `PROJECT` | Ownership guard: when set, the loop only picks tickets in this tracker project — protects multi-repo trackers from cross-repo picks. Empty = no guard. |

"Why didn't it pick my ticket" is almost always answered here: wrong label, wrong
state, a blocker relation, another repo's `PROJECT`, or the size judge relabelled it
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
| `MAX_REPAIRS` / `MAX_BUGFIXES` | Repair attempts before verify gives up and quarantines. |
| `SIZE_JUDGE` | Pre-flight sizing: flags too-large tickets with `SPLIT_LABEL` instead of burning a run on them. |

## Budgets

Hard spend rails — the loop stops rather than crossing them:

`MAX_TICKET_USD`, `MAX_TICKET_TOKENS`, `MAX_DAILY_USD`, `MAX_DAILY_TOKENS`.

A run that stopped "for no reason" may simply have hit one; `trau forensics spend
<ID>` and `trau --status` show the numbers.

## Verify

| Key | Meaning |
| --- | --- |
| `VERIFY_CHECKS` | `1` (default) runs the pluggable check library — repo-defined checks in `<repo>/.trau/checks/*.yaml`, or a built-in set (tests, typecheck, lint, anti-placeholder, anti-duplication). `error` severity blocks the merge. |
| `BROWSER_VERIFY` | `auto` (browser QA only for UI slices) \| `always` \| `never`. |
| `APP_URL` / `APP_URLS` | Where browser verify points; `APP_URLS` maps monorepo workspaces to URLs. |
| `VERIFY_PANEL` / `VERIFY_PANEL_POLICY` | Cross-vendor verify: N isolated verifiers from different providers, merged `unanimous` \| `majority` \| `any-pass`. |
| `QA_NOTES` | `1` (default) posts the run's QA report as a ticket comment on delivery or give-up. |

## Worktrees and parallelism

| Key | Meaning |
| --- | --- |
| `WORKTREES` | `0` (default) = one checkout, serial drain. `1` = each queued run gets its own worktree, branch, and PR. |
| `WORKTREE_PARALLEL` | Lanes per repo (default 4) — only meaningful with `WORKTREES=1`. |
| `WORKTREE_SETUP_CMD` | Runs in each fresh tree (e.g. `npm ci`); also where per-lane resource separation (DB, ports, caches) belongs. |
| `APP_START_CMD` | Serves the app from inside a worktree on a hub-allocated port (`$PORT`), so browser verify tests the branch under test. |

## The hub (`SERVE_*`)

| Key | Meaning |
| --- | --- |
| `SERVE_BIND` / `SERVE_PORT` | Default `127.0.0.1:8728`. |
| `SERVE_TOKEN` | Required the moment the bind leaves loopback — the hub refuses to start exposed without it; all requests then need `Authorization: Bearer`. |
| `SERVE_ALLOW_REGISTER` | `0` (default): on an exposed hub, (un)registering repos over the API is refused even with the token — a leaked token can't widen where agents run. |
| `SERVE_WORKSPACE` | Comma-separated repos the hub serves. |
| `SERVE_AUTOSTART` | `1` (default): starting `trau` brings the hub up first. |

## Providers and credentials

`CLAUDE_BIN` / `CLAUDE_FLAGS`, `CODEX_BIN` / `CODEX_FLAGS` / `CODEX_PROFILE`,
`KIMI_BIN` / `KIMI_FLAGS` configure the agent CLIs (machine-trust flags belong in
`~/.trau.ini`, not the repo file). Tracker credentials: `LINEAR_API_KEY` (enables
fast direct GraphQL alongside MCP), `JIRA_BASE_URL` / `JIRA_EMAIL` /
`JIRA_API_TOKEN`, `AZURE_ORG_URL` / `AZURE_PAT`. Secrets never belong in
`<repo>/.trau.ini` if the repo is shared — trau gitignores its files in the target
repo, but a home-dir baseline is still the safer place.
