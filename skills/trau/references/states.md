# States, gates, classes, and phases

Several separate vocabularies come back from the hub, and they answer different
questions. Read the one that matches what you are holding: a **queue item status** is
where one row stands, a **hold gate** is why the whole drain is waiting, a **failure
class** is how one run ended, a **pause reason** is the specific wall it hit, and a
**phase** is how far a checkpoint got.

Most of these mean *wait*, not *fix*. Names below are the wire values; the hub UI calls
the product **Cobble**, but every state, gate and class keeps its `trau`-era spelling.

## Queue item statuses

What `queue_status` reports per row (`internal/queue/queue.go`).

| Status | What it means | What an operator does |
| --- | --- | --- |
| `pending` | Queued and runnable; the drain will launch it. | Nothing. `start_queue` if the drain isn't armed. |
| `running` | A child process owns it right now. | Read `list_instances`. Never touch its tree. |
| `paused` | The run stopped on a condition a person or time clears — a blameless pause, a stop, a `faulted` class under `on_fault=halt`, or one of the person-waiting classes (`repair_loop`, `push_refused`, `connection_lost`, `provider_locked`, `login_required`, `github_app_not_installed`). | Read the failure class and reason, clear that one block, then `start_queue`. A row that also reports `held: true` was stopped per-item and is skipped by the drain until its own Resume or the next Start. |
| `failed` | The run faulted under `on_fault=skip`, or quarantined (`gave_up`) — a reject past `MAX_REVIEW_ROUNDS` included. Also what `trau --requeue` leaves before its own row restore. | `get_run` for the class; usually `resume_run` from the checkpoint, then re-arm. |
| `done` | Merged and settled — also by a merge on the forge that the 2-minute merge sweep saw. | Nothing. |
| `skipped` | The drain passed the row over *without running it* because it duplicates work already claimed — a ticket row that is also a sub-issue of an epic row queued ahead of it (reason `duplicate of <EPIC> sub-issue`). | Nothing; the epic carries it. This is **not** a fault — faults under `on_fault=skip` read `failed`. |
| `awaiting-merge` | A pull request waits on a person and trau no longer owns the merge: an epic's release handed to a human, a run whose process died while it waited on a merge (or on the review a forge requires under `DELIVERY=automerge`), a stacked layer whose CI is deferred to the stack merge, or an `awaiting-changes` row whose threads all got resolved. | Wait — the hub sweeps the forge every 2 minutes and settles the row itself when the PR merges. `retry_release` hands an **epic's** release back for a retry; for a ticket, merge it or let the person decide. |
| `awaiting-qa` | A **hold on a person** at a durable checkpoint. Either the `DELIVERY=stop` hold at the pull request after green CI (no `hold_reason`; the row's own `delivery` override wins over the repo), or a **verify-gate hold** before commit and PR, which applies under `DELIVERY=stop` only: `hold_reason` `browser_not_driven` (a UI slice passed verify with no browser driven while an app was reachable, ADR 0303) or `input_not_supplied` (verify could not exercise a path because Checklist input is open or unavailable; `input_missing` names the items, ADR 0304). The lane is freed, the worktree and app stay up. An epic holds once, at its release; a Folder epic that declares no child holds each sub-issue at its own child PRs, one after another. | The verdict is a person's — ask the user, send only their answer. PR hold: **Approve** (`approve_qa`) merges with `MERGE_METHOD` on the next pass; **Reject** (`reject_qa`, `notes` required — they become the fix round's steer note) re-enters at `handed_off` (an epic at `releasing`); a trusted reviewer's comment parks it `awaiting-changes`; a merge on the forge settles it `done`. Verify-gate holds: see § Run phases. Approve and Reject put the row `pending` at the *front* of the queue and arm the drain (`on_fault=halt`). The row **cannot be run or re-queued**: `run_queue_item` and `enqueue` refuse with `… holds on its pull request (awaiting-qa) — approve or reject it, or remove it from the queue first`. Not a hold gate; not a fault. |
| `awaiting-changes` | The PR drew review feedback the run could not close: a trusted reviewer requested changes or left an open thread (on a `DELIVERY=stop` PR too), feedback came from an author trau **cannot vouch for** (trust unknown — see `TRUSTED_REVIEWERS`), or the 2-minute review sweep found feedback after the run exited. | Usually wait: new trusted feedback while the drain is armed re-queues a review-fix session by itself; all threads resolved moves the row to `awaiting-merge` (a stop row back to `awaiting-qa`); an approval releases it. An unvouched-author park never auto-releases — add the author to `TRUSTED_REVIEWERS` or decide on the PR. `address_review` hands it back early; it starts nothing. Like `awaiting-qa`, `run_queue_item` and `enqueue` refuse it (`— address the review, or remove it from the queue first`). |
| `no-change` | Build and verify passed on an **empty diff** (ADR 0134): nothing to commit, so no push and no PR. The empty branch is deleted, the ticket gets the quarantine label with the verify summary, and the drain carries on whatever `on_fault` says. | A person decides what the ticket needs — often nothing, or a sharper description. `requeue_ticket` restores the row to `pending` like a failed one. Reminded like other human holds; not a fault. |
| `parked` | Settled for a reason the row itself names, before or after a run: an epic whose open children are all `not-ready` **and** none delivered (ADR 0326 — with one delivered child the epic finalizes instead); an epic whose own run ended **unfinalized** (ADR 0062 — one state, never `paused`); a sequential-group folder epic waiting on an unsettled sub-issue; a folder ticket under `WORKTREES=1` with no valid `Repo:` line. | Do the specific thing the reason names — label or close the children, merge or reset the child PR, add `Repo: <child>`. Parked rows re-evaluate after every issue sync, on Start and every 2 minutes while armed, and unpark to `pending` by themselves; on an idle queue Start still has to be pressed. `run_queue_item` on a parked epic re-checks it and runs it when a child has work (a child the epic run can resume counts); never requeue a parked epic to start it. |

`pending` and `paused` are the runnable statuses; the drain additionally skips a
`paused` row marked `held`. `awaiting-merge`, `awaiting-changes`, `awaiting-qa` and
`no-change` are the rows sitting on a human, re-notified every `HOLD_REMINDER_HOURS`; the
Queue page lists them under **Waiting on**, and the Backlog shows a ticket whose row holds
on its PR with `running` true and `hold` set to that status.
`parked` keeps a drain armed (it is work that may wake up), which is why an armed queue with only parked rows shows the `parked` gate rather
than disarming.

A **discarded** run (`discard_run`, `trau --discard`, ADR 0352) leaves no row at all: the
queue row and its sub-issue rows are force-removed, and the ticket carries the quarantine
label (`needs-human`) with the reason `run discarded by the operator`.

A row's `queued_by` (`id`, `name`) names the hosted Collaborator who queued it; that run
pushes, opens its PR and writes the tracker with *their* personal connections (ADR 0331).
Absent means the Operator.

If a row ever reads `awaiting-pick`, it predates the pick gate's removal (ADR 0059);
the migration turns those into `failed` with the reason "pick gate removed — re-queue
the ticket", and `requeue_ticket` is the remedy.

## Hold gates

What `queue_status.held_gate` reports when `held` is true
(`internal/webserver/drainhold.go`). The gate is what separates a deliberate wait from
a symptom; `held_reason` and `held_since` say which instance and since when.

### Deliberate waits — do not "fix" these

The hub's Loop screen tones these `info`: each ends by itself.

| Gate | Why the drain is waiting |
| --- | --- |
| `blocked` | Every runnable row has an unresolved blocker. A blocked-by edge between epics of two Projects in one hub **Workspace** counts too, and holds until the blocker is done in its own repo (ADR 0139). |
| `self-reload` | A hub self-reload is pending and waiting for hub-wide idle. |
| `repo-busy` | A serial repo already has its one run in flight — or, in a folder repo, an *in-place* item is waiting on another in-place run (isolated folder lanes never hold here). Also raised when an epic is running ("an epic holds the whole repo") or the next row *is* an epic that must start alone. |
| `release` | An epic is releasing — merging its stack — and holds the repo while it does. |
| `publish` | A Publish session holds the repo's queue (ADR 0053). Not the same thing as `release`. |
| `branch-held` | A branch a queued item needs is checked out in another worktree; it starts when that lane frees it. |
| `app-session` | An App session (the hub's App page) holds the repo's checkout, and the next row would run in that checkout or change it. The Loop page reads `Waiting on the App`, the run log `waiting for <checkout>`. Not a fault: never requeue, reset or quarantine for it — ask the user to stop the app on the App page, or to turn on worktrees so the ticket runs in its own lane (`references/hub-features.md` § App page). |
| `daily-cap` | A `QUEUE_AUTO_DRAIN` repo's run came back `capped`; the drain starts nothing until local midnight (`daily budget reached, resumes after <date>`). |

`held_gate: idle` is not a spawn hold at all: a `QUEUE_AUTO_DRAIN` drain that is armed
with nothing to run (`armed, waiting for ready tickets`) and waits for the next issue
sync. Nothing is wrong.

### Waits on a person

Toned `warn`: nothing clears these until someone acts — except the `update` hold's
auto-update form, which clears itself.

| Gate | What it needs |
| --- | --- |
| `team-drift` | The committed `.trau/config.team.ini` states a merge-affecting key (`DELIVERY`, `REQUIRE_CI`) differently from what the repo runs with. `queue_status.held_drift` lists the keys with both values. Relay both to the user: fix the config, or — on their answer — re-arm with `start_queue acknowledge_drift=[…]` repeating that exact set. |
| `parked` | Every queued row is parked and the loop may pick none of them (formerly `parked-epic`; now covers parked tickets too). `held_reason` carries the single row's reason when there is one. Unparks itself when a row becomes pickable. |
| `license` | The installation's entitlement is `locked` and enforced; the reason reads `this trau installation is locked: <cause> — buy a license at <url> …`. Report it and stop — no retry clears it; lanes that started before the lock still finish. |
| `update` | Two reasons. `held: update required (vX → vY)` — the **update lock** (ADR 0322): a release-channel, non-hosted hub with `UPDATE_CHECK=1` that has known of a newer release for 8 wall-clock hours (a durable clock; a restart does not reset it) refuses every new start of agent work. Ask the user to approve `trau update` or **Settings → Updates**; never set `UPDATE_CHECK=0` to get around it unless they ask. `held: restarting onto vY` — `AUTO_UPDATE` (default on) already installed the release and the hub restarts at the next ticket boundary once runs in flight finish; it clears by itself, so do not disarm or restart for it. Either way the drain stays armed and picks again on the new version. |

### Symptoms — worth reading into

| Gate | What it points at |
| --- | --- |
| `queue-error` | The drain could not read or write the queue. The hub retries on the next tick. |
| `launch-failed` | A child could not be spawned. The hub retries on the next tick. |
| `stalled` | Synthesised after **2 minutes** in which the drain loop reached no decision at all — armed, with nothing draining it. |

The PR hold and the verify-gate holds are **not** on this list. They are not gates: they
are the item status `awaiting-qa`. The three-way split follows the hub's own tones
(`info` for the deliberate waits; `warn` for the rest); splitting `warn` into "person" and
"symptom" is this reference's reading.

### Refusals that are not gates

A start can be refused before any row moves. Relay the sentence; do not retry around it.

- ``Update required: this hub runs vX, vY is available. Install it in Settings → Updates or run `trau update`.``
  — the update lock refuses every start of agent work: a manual run, a Resume that starts
  the run, `reverify_run`, `settle_adr_conflict`, an Interview start or resume, a draft
  from a report or a polled issue, an Atlas trace, an Assistant thread and a checklist
  check or do-run (REST `409 update_required`). Reads, Settings, config, `trau update` and
  a hub restart stay open; runs in flight finish.
- `this trau installation is locked: …` — the license gate.
- `provider_not_ready` (a Start whose Provider is not installed or signed in — read
  `list_provider_readiness`) and `browser_harness_unavailable` (browser verify is on and
  no harness can open a lease — `trau browser setup`, then `trau browser status`).
- A hosted Collaborator's queue write: `409 connection_required` with `service` (`github`
  or `tracker`) — their personal connection is missing; never re-queue it with the
  operator token.

## Failure classes

`get_run.failure_class` (checkpoint `FAILURE_CLASS`, `internal/state/state.go`) is how
a run *ended*. Note the underscore spelling — the hyphenated forms are queue statuses.

| Class | What happened | Queue row |
| --- | --- | --- |
| `paused` | A blameless wall — see pause reasons below. | `paused` |
| `faulted` | Something operational broke around the attempt: expired `gh` auth, a wrong upstream, a mis-pathed provider CLI, a pre-push hook that rejected the push (`pre-push hook rejected: …`), a failed worktree setup step, lane database copy or lane Supabase stack. | `paused` under `on_fault=halt`, `failed` under `skip` |
| `gave_up` | The run quarantined the ticket — see § Quarantine below. | `failed` |
| `stopped` | Ended on purpose: loop Stop, per-item Stop, or `stop_instance`. Never auto-resumed. | `paused` |
| `repair_loop` | A verify failure repeated an earlier round of the same run — A, A, A or A, B, A (ADR 0311). The reason names the repeated rounds and the top failure line of each; the ticket carries `needs-human`. A resume re-arms the check. | `paused` |
| `push_refused` | The remote refused the push for a credential or a permission (a token without the `workflow` scope, say). | `paused` |
| `connection_lost` | A hosted Collaborator's own GitHub or tracker connection gave no token any more; the ticket carries `needs-human`. It never falls back to the hub's connections (ADR 0331). | `paused` |
| `provider_locked` | The launch Provider is outside the license's provider lock (`ALLOWED_PROVIDERS`). | `paused` |
| `login_required` | The login gate requires an account and the Provider is not signed in. | `paused` |
| `github_app_not_installed` | The GitHub Connection cannot reach the repo: trau's GitHub App is not installed on the owner the reason names (ADR 0327). | `paused` |
| `awaiting_changes` | Parked on review feedback. | `awaiting-changes` |
| `awaiting_merge` / `awaiting_qa` | Human holds carried as classes. | `awaiting-merge` / `awaiting-qa` |
| `requeued` | Transient: the child could not take its branch or worktree because a *live* lane holds it; the row went back to `pending` and the drain waits for the holder. | `pending` |
| `held` | The run filed a ticket in a sibling repo of its Workspace and waits behind that blocked-by edge; it keeps its branch and the queue re-picks it when the edge resolves (ADR 0221). | `pending` |
| `capped` | An epic child loop hit `--once`, `MAX_ITERATIONS` or the daily budget with open children left after shipping at least one; the row went back to `pending`. Not a quarantine. Under `QUEUE_AUTO_DRAIN` it also holds the drain `daily-cap` until midnight. | `pending` |
| `no_change` | Build and verify passed on an empty diff; nothing was committed or pushed and no PR opened (ADR 0134). The reason starts `no-change:`. The checkpoint stays at `verified`; the automatic resume scan skips it, and an explicit resume re-enters at `verified` and settles the same way. For an epic, a no-change child is left out of the delivery; an epic whose children all ended no-change delivers nothing. | `no-change` |

The six person-waiting classes (`repair_loop`, `push_refused`, `connection_lost`,
`provider_locked`, `login_required`, `github_app_not_installed`) are never auto-resumed:
do not `resume_run` one until the person has done the thing its reason names.

A run with no class and phase `merged` simply finished; phase `quarantined` reads as
`gave_up` even when nothing else is stamped.

### Quarantine

`gave_up` means the run parked the ticket for a human (`needs-human`). At HEAD the
causes are: verify still failing when an *explicit* `MAX_BUGFIXES=N` ran out (the
default is unlimited — a default-config run keeps bugfixing until verify passes, a
budget cap stops it, or a repeat pauses it `repair_loop`); a **red** CI check after
repairs (a *pending* check never quarantines — ADR 0274, see `ci_pending`); an
`EXPECTED_CHECKS` name no green check matched by `CI_TIMEOUT` with nothing pending; the
PR (or epic PR) closed without merge; conflicts with the base that cannot be synced; a
budget cap reached; the fix rounds (`MAX_REVIEW_ROUNDS`, default 10 — review-comment
rounds and `DELIVERY=stop` Reject rounds share the one counter) exhausted on a **ticket**
PR (an epic PR parks `awaiting-changes` instead); a QA fix round that left the PR head
unchanged; no PR or branch left to merge. The reason string names which. Editing tracker
labels by hand never revives a quarantined ticket.

## Pause reasons

How a `paused` run explains itself. The pipeline emits a short reason token; the run
page folds these into eight kinds (`hook_rejected`, `branch_held`, `tool_unavailable`,
`adr_conflict`, `dialog`, `reauth`, `usage_window`, `other`). The hub offers **Ask the
Assistant** on a halt, which only opens a draft Conversation; it no longer generates
copy-paste Unblock prompts. External agents diagnose and recover with the hub tools.

| Reason | What happened | What clears it |
| --- | --- | --- |
| `adr_conflict` | `ADR_POLICY`'s cold verifier read the diff as contradicting an accepted ADR the issue never authorized superseding. Reason starts `ADR conflict needs human input: ` and names the ADR paths. Not a failure. Editing the issue does **not** clear it — the verifier reads the handoff brief, not the tracker. | Only a person decides: ask the user, never decide yourself. `settle_adr_conflict decision=authorize` (`trau adr authorize <ID>`) authorizes superseding exactly those paths for the life of the ticket and resumes at verify; `decision=keep note="…"` (`trau adr keep <ID> --note "…"`) re-enters repair from the note. Either also resumes the run. Never auto-resumed. |
| `adr_dir` | `ADR_POLICY` cannot run: `ADR_DIR` is absolute, escapes the repo or leaves it through a symlink (`ADR policy cannot run: …`). Branch and checkpoint kept. | Point `ADR_DIR` inside the repo, then resume. |
| `local_merge_blocked` | A remote-less repo's local squash-merge is held: the checkout holding the base is on another branch or detached, mid-merge/rebase, has staged changes, or has uncommitted paths the ticket branch also writes (`the local merge into <base> is held …`, ADR 0097). Nothing in that checkout was changed. | That work is the user's — tell them; never commit, move or discard it yourself. `resume_run` checks again. |
| `dialog` | The agent is standing at an interactive prompt and cannot answer it. Not a failure. When the reason says *a command confirmation an unattended run cannot answer*, Claude Code asked to confirm one command and trau declined it (ADR 0116) — nothing on the machine needs clearing. | For a question: answer it once in an interactive session of that provider on the hub's machine — or `steer_agent kind=keys` while watching the terminal. For a command confirmation: read the command in the transcript, then resume. (`trau tools install` seeds Claude's and Codex's first-run settings so a first-run dialog does not stop a run.) |
| `reauth` | A provider auth wall. | The person re-authenticates. |
| `usage_window` | A provider rate or usage limit. | Time. |
| `tool_unavailable` | A helper the build agent needed — Serena, a language server, a browser — was unreachable (`tool unavailable: <tool> — … → fix: …`). Branch and checkpoint are kept; the reason names the fix command. | Apply the named fix, then Start or `resume_run`. When the fix is `trau browser setup --system` (missing OS packages) it needs a person at that machine and is never auto-resumed. |
| `worktree_held` (shown as `branch_held`) | git allows a branch one worktree at a time, and the tree holding it belongs to no live run. (When the holder *is* live the class is `requeued` instead and the drain simply waits.) | Confirm nothing live owns it, then free the branch — never by removing a worktree the hub owns. |
| `forge_outage` | The code host errored or the network never reached it. The checkpoint stays put; verified work is **not** re-run when the forge comes back. | Time. |
| `ci_pending` | A CI check was still running at `CI_PENDING_TIMEOUT` (default 3600 s; `CI_TIMEOUT` now bounds only the time for checks to appear and settle). Reason: `CI wait timed out after … still running (<checks>); raise CI_PENDING_TIMEOUT or resume the run once it finishes`. No tracker label (ADR 0274). | Resume once the check finishes — the resume waits for the checks again. `QUEUE_AUTO_RESUME` may re-attempt it. |
| `ci_unreadable` | Every poll `failed to read the pull request's checks`; there is no CI verdict and trau never merges without one. | Ask the user to fix the forge CLI or its sign-in, then `resume_run`. |
| `provider_unavailable` | The item is pinned to a provider that is not installed (`provider unavailable: …`). The hub also raises one `provider_unavailable` notification per project, Provider and cause (`not_installed`, `not_signed_in`, `probe_error`, `usage_limit`, `out_of_credit`, `auth_wall`, `unavailable`; ADR 0295). | Install it (`trau tools install <tool>` or the hub's Install, by the user) or clear the pin. |
| `provider_switch` | A `switch_provider` restart's replacement call failed before any process started (`provider switch to <p> failed: …`). The ticket keeps `PROVIDER_SWITCH` for the resume (ADR 0272). | Fix what kept the target Provider from starting, then resume. |
| `input_not_supplied` | The user **rejected** an `input_not_supplied` verify-gate hold (`the operator rejected the run without its Checklist input: <items>`). | Supply or waive each item (§ operations, Operator checklist), then `resume_run`. |
| `sibling_request` | The run asked for work in a sibling repo and the request was malformed or refused (`sibling request needs human input: …`); the ticket carries `needs-human`. | A person decides what the sibling repo needs, then resume. Never auto-resumed. |
| `hub_unreachable` | Run data could not be saved within `HUB_WRITE_RETRY_WINDOW` (30 s). | The hub back up; then Start. |
| `commit_probe_failed` | Every trial commit in the tree fails — identity or hook misconfiguration — caught before the first agent call. | Fix git identity / hooks. |
| `delivery_not_ready` | The repo cannot be delivered to (gh auth, remote) — caught before Build. | Fix auth or the remote. |
| `browser_verify` | Browser verify could not run when it had to: `BROWSER_VERIFY=always` with no reachable app URL or automation browser, a UI slice still undriven after its one re-verify, or a `browser_not_driven` hold the user rejected that re-verified still undriven (`browser verify required but not run…`). | Fix `APP_URL` / the browser; `trau doctor` and `trau browser status` name it. |
| `skill_missing` / `skill_unnameable` | A skill routed `scope: always` is not installed or cannot be loaded from the run dir. | Install the skill; `trau doctor` *skills*. |
| child exited without a drain report | The drain child died before its first event (a crash, a killed process). The row carries `has_log`. | `trau forensics log <ID>` for the last lines, fix, Start. |

A pre-push hook rejection is a **fault**, not a pause (`faulted`, reason
`pre-push hook rejected: …`); it is never auto-resumed. Fix the failing check the
folded rejection names, on the run's branch — a bare re-attempt fails the same way.

`QUEUE_AUTO_RESUME=1` re-attempts a row whose class is `paused` on a backoff
(2 min × attempt, `QUEUE_AUTO_RESUME_TRIES` default 2) — every reason above **except**
`adr_conflict`, `sibling_request` and a `tool_unavailable` waiting on
`trau browser setup --system`; never one of the six person-waiting classes, never a
`held` row, never a fault or a stop. A crashed epic *release* gets two automatic
re-attempts even with the key off.

### Conditions that do not pause

Under `DELIVERY=automerge` the two verify-gate conditions do **not** hold the run: it
continues past the gate, merges, and `get_run.notices` reports `input_not_supplied`
(with `items`) or `browser_not_driven`; the PR body lists each unexercised input. There
is nothing to approve (ADR 0345). Checklist input never holds a run on any other path
(ADR 0276).

## Run phases

Where a checkpoint sits (`internal/state/state.go`). The order is stable across
versions, so "earlier phase" always means "got less far".

```
building → built → handed_off → verified → pr_open → releasing | awaiting-qa | conformance → merged
```

| Phase | Reached when |
| --- | --- |
| `building` | The build agent is working. Under `WORKTREES=1` the run first reports pre-build stages `worktree/fetch`, `worktree/create`, `worktree/database`, `worktree/setup:<step>`. |
| `built` | The build finished. |
| `handed_off` | The handoff brief is written. |
| `verified` | Verify passed. A `no_change` run settles *here* (empty diff, no PR), and the resume scan skips it. |
| `pr_open` | The pull request exists. A ticket's `awaiting-merge` and `awaiting-changes` park *here*; the checkpoint's `PR_STATUS` (`awaiting-merge`, `awaiting-changes`, `review-fix`, `merged`, `closed`) says why. |
| `releasing` | An epic is merging its stack. `RELEASE=active` means trau owns it; `awaiting-human` means it was handed off — an epic's `awaiting-merge` and review parks sit here, not at `pr_open`. |
| `awaiting-qa` | The durable checkpoint of every hold on a person (`HOLD_REASON` empty for the `DELIVERY=stop` PR hold). The resume scan skips it unless `QA_APPROVED=1`. PR hold: a Reject re-enters at `handed_off` (an epic at `releasing`) with the notes; a reject past the last round quarantines. `browser_not_driven`: Approve continues at `verified` (the PR body says the browser QA was accepted); Reject re-verifies once with the browser required, spends no fix round, and pauses `browser_verify` if still undriven. `input_not_supplied`: Approve continues past the gate when every held item is waived (the PR body lists each waiver), otherwise re-verifies once; Reject pauses `input_not_supplied`. `advance_run` never answers this phase. |
| `conformance` | A done epic's one **conformance pass** is running (ADR 0305; rank 6, beside `releasing` and `awaiting-qa`); the checkpoint returns to its earlier phase after it. A re-verify (`reverify_run`) of a shipped ticket runs the same pass. |
| `merged` | Landed on the base branch. Terminal. |
| `quarantined` | Terminal, off the ladder: the run gave up and parked the ticket for a human. `resume_run` can still re-enter it when the checkpoint holds a PR, commit or branch. |

### Conformance results

The conformance pass is a result, never a gate: it never blocks, reopens or re-statuses
the epic. With `CONFORMANCE=1` (default) it runs once after an epic is done, in a fresh
lane at the merged base (it needs `WORKTREES=1`; without a lane it records a `skipped`
result), and grades the base against the decision-board picks of the epic and its
children, the Interview's clarifications and the epic acceptance criteria. Read it with
`get_artifact kind=conformance`: the deviation list (kind, reference, expected, observed,
proofs), the count checked, the browser state and a summary. A pass with a deviation
raises an `epic_conformance` notification. `get_run` reports `conformance_running` while a
pass runs and the earlier results under `previous`; a deviation the user left out of the
pass's one fix ticket comes back on the next pass with `accepted_by_operator: true`
(ADR 0306). An agent error, no lane or a malformed verdict records `skipped` and nothing
retries.

### Epic finalize rules

An epic finalizes — opens or adopts its epic-to-base PR and is marked Done — when it has
**no holding child and at least one delivered child** (ADR 0326). A child is *not ready*
only when it is held (`trau-hold-v1`), lacks `READY_LABEL` when the repo sets one, or lacks
any `PICK_LABELS`; tracker status does not change that.

| Children | Outcome |
| --- | --- |
| A ready todo child with no open blocker | The drain runs it |
| A holding child: ready but blocked, running or checkpointed, nested parent, unknown status | Parks |
| Only not-ready children, none delivered | Parks, naming how to unblock |
| Not-ready children plus at least one delivered | Finalizes; the not-ready children stay open and untouched (status text `Delivered: <ids>. Left open, not ready: <ids>.`) |
| Every child delivered | Finalizes |

A left-open child that is labelled ready later runs on its own on `BASE_BRANCH`, or in a
new epic run when the epic is queued again. Under `DELIVERY=stop` the epic holds once, at
its release PR (`awaiting-qa`); its children never hold.

`list_runs` comes back in board order — earliest phase first, then ticket — so the
stuck runs lead. Neither it nor `trau forensics runs` sorts by recency: sort
client-side when the question is "what settled last".

## Instance session states

`list_instances.session_state` is a fifth vocabulary about the *live process*, not the
row: `idle`, `grazing` (waiting for a pick), `working`, `parked` (a live session
waiting on something), `stopping`, `takeover`. Its `parked` is unrelated to the queue
status `parked` — a live instance can be parked while its row reads `running`.
`agent_call` and `agent_phase` name the agent call in flight (what `switch_provider`
addresses); `provider_switch` is the run's latest switch, `pending` → `claimed` →
`applied` or `failed`.

## Cadences worth knowing

Drain tick 2 s · stall synthesised after 2 min · forge merge sweep, review sweep,
parked-row re-evaluation and misfiled-hold repair every 2 min · issue sync every
`SERVE_SYNC_INTERVAL` (120 s) — the tick on which `QUEUE_AUTO_DRAIN` enqueues ready
tickets · human-hold reminder sweep every 5 min, re-notifying every
`HOLD_REMINDER_HOURS` (default 24) · Sentry Monitoring poll every
`SENTRY_POLL_INTERVAL` (5 min) · hosted repository refresh every 15 min · release check
daily, update lock 8 h after a newer release is first seen · calibration sweep at hub
start and every 24 h · `HUB_PEER_URL` heartbeat every 30 s · stale zero-byte
`index.lock` removed by trau after ~15 s of retries.
