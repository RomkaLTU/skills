# States, gates, classes, and phases

Several separate vocabularies come back from the hub, and they answer different
questions. Read the one that matches what you are holding: a **queue item status** is
where one row stands, a **hold gate** is why the whole drain is waiting, a **failure
class** is how one run ended, a **pause reason** is the specific wall it hit, and a
**phase** is how far a checkpoint got.

Most of these mean *wait*, not *fix*.

## Queue item statuses

What `queue_status` reports per row (`internal/queue/queue.go`).

| Status | What it means | What an operator does |
| --- | --- | --- |
| `pending` | Queued and runnable; the drain will launch it. | Nothing. `start_queue` if the drain isn't armed. |
| `running` | A child process owns it right now. | Read `list_instances`. Never touch its tree. |
| `paused` | The run stopped on a condition a person or time clears — or someone pressed Stop. | Read the failure class and reason, clear that one block, then `start_queue`. A row that also reports `held: true` was stopped per-item and is skipped by the drain until its own Resume or the next Start. |
| `failed` | The run faulted (or gave up) and the queue settled the row. Also what `on_fault=skip` leaves behind, and what `trau --requeue` leaves before its own row restore. | `get_run` for the class; usually `resume_run` from the checkpoint, then re-arm. |
| `done` | Merged and settled. | Nothing. |
| `skipped` | The drain passed the row over *without running it* because it duplicates work already claimed — a ticket row that is also a sub-issue of an epic row queued ahead of it (reason `duplicate of <EPIC> sub-issue`). | Nothing; the epic carries it. This is **not** a fault — faults under `on_fault=skip` read `failed`. |
| `awaiting-merge` | A pull request is green and waits on a person: an epic's release handed to a human, a ticket with `AUTO_MERGE=0`, a run whose process died while it waited on a merge or a `REVIEW_GATE` verdict, a stacked layer whose CI is deferred to the stack merge, or an `awaiting-changes` row whose threads all got resolved. | Wait — the hub sweeps the forge every 2 minutes and settles the row itself when the PR merges. `retry_release` hands an **epic's** release back for a retry; for a ticket, merge it or let the person decide. |
| `awaiting-qa` | `QA_GATE` (or the item's own Hold-for-QA choice) held the run after green CI, before the merge, at a durable checkpoint. Its lane is freed; its worktree and app stay up. | Nothing — a person releases it with **Approve** (row goes `pending` at the *front* of the queue) or **Reject** (a bounded QA fix round, 2 max) on the run page. No MCP tool does this. Not a hold; not a fault. |
| `awaiting-changes` | The PR drew review feedback the run could not close: a trusted reviewer requested changes or left an open thread, feedback came from an author trau **cannot vouch for** (trust unknown — see `TRUSTED_REVIEWERS`), or the 2-minute review sweep found feedback after the run exited. | Usually wait: new trusted feedback while the drain is armed re-queues a review-fix session by itself; all threads resolved moves the row to `awaiting-merge`; an approval releases it. An unvouched-author park never auto-releases — add the author to `TRUSTED_REVIEWERS` or decide on the PR. `POST …/runs/{ticket}/address-review` hands it back early. |
| `parked` | Settled for a reason the row itself names, before or after a run: an epic whose open children are all `not-ready`; an epic whose own run ended **unfinalized** (ADR 0062 — one state, never `paused`); a sequential-group folder epic waiting on an unsettled sub-issue; a folder ticket under `WORKTREES=1` with no valid `Repo:` line. | Do the specific thing the reason names — label or close the children, merge or reset the child PR, add `Repo: <child>`. Parked rows re-evaluate after every issue sync, on Start and every 2 minutes while armed, and unpark to `pending` by themselves; on an idle queue Start still has to be pressed. |

`pending` and `paused` are the runnable statuses; the drain additionally skips a
`paused` row marked `held`. `parked` keeps a drain armed (it is work that may wake
up), which is why an armed queue with only parked rows shows the `parked` gate rather
than disarming.

If a row ever reads `awaiting-pick`, it predates the pick gate's removal (ADR 0059);
the migration turns those into `failed` with the reason "pick gate removed — re-queue
the ticket", and `requeue_ticket` is the remedy.

## Hold gates

What `queue_status.held_gate` reports when `held` is true
(`internal/webserver/drainhold.go`). The gate is what separates a deliberate wait from
a symptom; `held_reason` and `held_since` say which instance and since when.

### Deliberate waits — do not "fix" these

| Gate | Why the drain is waiting |
| --- | --- |
| `blocked` | Every runnable row has an unresolved blocker. |
| `self-reload` | A hub self-reload is pending and waiting for hub-wide idle. |
| `repo-busy` | A serial repo already has its one run in flight — or, in a folder repo, an *in-place* item is waiting on another in-place run (isolated folder lanes never hold here). Also raised when an epic is running ("an epic holds the whole repo") or the next row *is* an epic that must start alone. |
| `release` | An epic is releasing — merging its stack — and holds the repo while it does. |
| `publish` | A Publish session holds the repo's queue (ADR 0053). Not the same thing as `release`. |
| `branch-held` | A branch a queued item needs is checked out in another worktree. |
| `team-drift` | The committed `.trau/config.team.ini` states a merge-affecting key (`AUTO_MERGE`, `REVIEW_GATE`, `REQUIRE_CI`) differently from what the repo runs with. `queue_status.held_drift` lists the keys with both values. Fix the config, or re-arm with `start_queue acknowledge_drift=[…]` repeating that exact set. |
| `parked` | Every queued row is parked and the loop may pick none of them (formerly `parked-epic`; now covers parked tickets too). `held_reason` carries the single row's reason when there is one. Unparks itself when a row becomes pickable. |

### Symptoms — worth reading into

| Gate | What it points at |
| --- | --- |
| `queue-error` | The drain could not read or write the queue. |
| `launch-failed` | A child could not be spawned. |
| `stalled` | Synthesised after **2 minutes** in which the drain loop reached no decision at all — armed, with nothing draining it. |

The QA gate is **not** on this list. It is not a hold: it is the item status
`awaiting-qa`. The waits-vs-symptoms split is this reference's reading; the source
only distinguishes gates it logs as errors (`queue-error`, `launch-failed`) plus the
synthesised `stalled`.

## Failure classes

`get_run.failure_class` (checkpoint `FAILURE_CLASS`, `internal/state/state.go`) is how
a run *ended*. Note the underscore spelling — the hyphenated forms are queue statuses.

| Class | What happened | Queue row |
| --- | --- | --- |
| `paused` | A blameless wall — see pause reasons below. | `paused` |
| `faulted` | Something operational broke around the attempt: expired `gh` auth, a wrong upstream, a mis-pathed provider CLI, a pre-push hook that rejected the push (`pre-push hook rejected: …`). | `paused` under `on_fault=halt`, `failed` under `skip` |
| `gave_up` | The run quarantined the ticket — see § Quarantine below. | `failed` |
| `stopped` | Ended on purpose: loop Stop, per-item Stop, or `stop_instance`. Never auto-resumed. | `paused` |
| `awaiting_changes` | Parked on review feedback. | `awaiting-changes` |
| `awaiting_merge` / `awaiting_qa` | Human holds carried as classes. | `awaiting-merge` / `awaiting-qa` |
| `requeued` | Transient: the child could not take its branch or worktree because a *live* lane holds it; the row went back to `pending` and the drain waits for the holder. | `pending` |
| `capped` | An epic child loop hit `--once`, `MAX_ITERATIONS` or the daily budget with open children left after shipping at least one; the row went back to `pending`. Not a quarantine. | `pending` |

A run with no class and phase `merged` simply finished; phase `quarantined` reads as
`gave_up` even when nothing else is stamped.

### Quarantine

`gave_up` means the run parked the ticket for a human. At HEAD the causes are: verify
still failing when an *explicit* `MAX_BUGFIXES=N` ran out (the default is unlimited —
a default-config run keeps bugfixing until verify passes or a budget cap stops it);
CI not green after repairs; the PR (or epic PR) closed without merge; conflicts with
the base that cannot be synced; a budget cap reached; the review fix rounds
(`MAX_REVIEW_ROUNDS`, default 10) exhausted on a **ticket** PR (an epic PR parks
instead); no PR or branch left to merge. The reason string names which.

## Pause reasons

How a `paused` run explains itself. The pipeline emits a short reason token; the run
page folds these into seven kinds (`hook_rejected`, `branch_held`, `tool_unavailable`,
`dialog`, `reauth`, `usage_window`, `other`). The hub emits a copy-paste **Unblock
prompt** for every kind except `reauth` and `usage_window`, because no amount of work
clears those.

| Reason | What happened | What clears it |
| --- | --- | --- |
| `dialog` | The agent is standing at an interactive prompt and cannot answer it. Not a failure. | Answer it once in an interactive session of that provider on the hub's machine — or `steer_agent kind=keys` while watching the terminal. (Claude Code's folder-trust dialog is pre-accepted now and no longer causes this.) |
| `reauth` | A provider auth wall. | The person re-authenticates. |
| `usage_window` | A provider rate or usage limit. | Time. |
| `tool_unavailable` | A helper the build agent needed — Serena, a language server, a browser — was unreachable. Branch and checkpoint are kept; the reason names the fix command. | Apply the named fix, then Start or `resume_run`. |
| `worktree_held` (shown as `branch_held`) | git allows a branch one worktree at a time, and the tree holding it belongs to no live run. (When the holder *is* live the class is `requeued` instead and the drain simply waits.) | Confirm nothing live owns it, then free the branch — never by removing a worktree the hub owns. |
| `forge_outage` | The code host errored or the network never reached it. The checkpoint stays put; verified work is **not** re-run when the forge comes back. | Time. |
| `provider_unavailable` | The item is pinned to a provider that is not installed. | Install it or clear the pin. |
| `hub_unreachable` | Run data could not be saved within `HUB_WRITE_RETRY_WINDOW` (30 s). | The hub back up; then Start. |
| `commit_probe_failed` | Every trial commit in the tree fails — identity or hook misconfiguration — caught before the first agent call. | Fix git identity / hooks. |
| `delivery_not_ready` | The repo cannot be delivered to (gh auth, remote) — caught before Build. | Fix auth or the remote. |
| `browser_verify` | Browser verify was required but could not run: no reachable app URL or automation browser. | Fix `APP_URL` / the browser; `trau doctor` names it. |
| `skill_missing` / `skill_unnameable` | A skill routed `scope: always` is not installed or cannot be loaded from the run dir. | Install the skill; `trau doctor` *skills*. |
| child exited without a drain report | The drain child died before its first event (a crash, a killed process). The row carries `has_log`. | `trau forensics log <ID>` for the last lines, fix, Start. |

A pre-push hook rejection is a **fault**, not a pause (`faulted`, reason
`pre-push hook rejected: …`); it is never auto-resumed. Fix the failing check the
folded rejection names, on the run's branch — a bare re-attempt fails the same way.

`QUEUE_AUTO_RESUME=1` re-attempts any row whose class is `paused` — every reason
above — on a backoff (2 min × attempt, `QUEUE_AUTO_RESUME_TRIES` default 2); never a
`held` row, never a fault or a stop. A crashed epic *release* gets two automatic
re-attempts even with the key off.

## Run phases

Where a checkpoint sits (`internal/state/state.go`). The order is stable across
versions, so "earlier phase" always means "got less far".

```
building → built → handed_off → verified → pr_open → releasing | awaiting-qa → merged
```

| Phase | Reached when |
| --- | --- |
| `building` | The build agent is working. Under `WORKTREES=1` the run first reports pre-build stages `worktree/fetch`, `worktree/create`, `worktree/database`, `worktree/setup:<step>`. |
| `built` | The build finished. |
| `handed_off` | The handoff brief is written. |
| `verified` | Verify passed. |
| `pr_open` | The pull request exists. A ticket's `awaiting-merge` and `awaiting-changes` park *here*; the checkpoint's `PR_STATUS` (`awaiting-merge`, `awaiting-changes`, `review-fix`, `merged`, `closed`) says why. |
| `releasing` | An epic is merging its stack. `RELEASE=active` means trau owns it; `awaiting-human` means it was handed off — an epic's `awaiting-merge` and review parks sit here, not at `pr_open`. |
| `awaiting-qa` | The QA gate's durable checkpoint. The resume scan skips it unless `QA_APPROVED=1`. |
| `merged` | Landed on the base branch. Terminal. |
| `quarantined` | Terminal, off the ladder: the run gave up and parked the ticket for a human. `resume_run` can still re-enter it when the checkpoint holds a PR, commit or branch. |

`list_runs` comes back in board order — earliest phase first, then ticket — so the
stuck runs lead. Neither it nor `trau forensics runs` sorts by recency: sort
client-side when the question is "what settled last".

## Instance session states

`list_instances.session_state` is a fifth vocabulary about the *live process*, not the
row: `idle`, `grazing` (waiting for a pick), `working`, `parked` (a live session
waiting on something), `stopping`, `takeover`. Its `parked` is unrelated to the queue
status `parked` — a live instance can be parked while its row reads `running`.

## Cadences worth knowing

Drain tick 2 s · stall synthesised after 2 min · forge merge sweep, review sweep,
parked-row re-evaluation and misfiled-hold repair every 2 min · human-hold reminder
sweep every 5 min, re-notifying every `HOLD_REMINDER_HOURS` (default 24) · stale
zero-byte `index.lock` removed by trau after ~15 s of retries.
