# States, gates, and phases

Four separate vocabularies come back from the hub, and they answer different
questions. Read the one that matches what you are holding: a **queue item status**
is where one row stands, a **hold gate** is why the whole drain is waiting, a
**pause class** is why one run stopped, and a **phase** is how far a checkpoint got.

Most of these mean *wait*, not *fix*.

## Queue item statuses

What `queue_status` reports per row.

| Status | What it means | What an operator does |
| --- | --- | --- |
| `pending` | Queued and runnable; the drain will launch it. | Nothing. `start_queue` if the drain isn't armed. |
| `running` | A child process owns it right now. | Read `list_instances`. Never touch its tree. |
| `paused` | The run stopped on a condition a person or time clears. | Read the pause class below, clear that one block, then `start_queue`. |
| `failed` | The run faulted and the queue settled the row. | `get_run` for the class; usually `resume_run` from the checkpoint, then re-arm. |
| `done` | Merged and settled. | Nothing. |
| `skipped` | A fault under `on_fault=skip` — settled so the drain could continue. | Same as `failed`, once the drain finishes. |
| `awaiting-merge` | An epic's stack merge gave up and handed the merge to a person. | Wait — the hub sweeps the forge every 2 minutes and resumes itself. `retry_release` to hand it back for a retry. |
| `awaiting-qa` | `QA_GATE` held the run after green CI, before the merge, at a durable checkpoint. Its lane is freed; its worktree and app stay up. | Nothing — a person releases it with **Approve** on the run page. Not a hold; not a fault. |
| `awaiting-pick` | The run is held at the UI pick gate, or exhausted `PICK_ROUNDS` regenerating variants. | A person picks a variant. The tree stays up to hand-edit. |
| `awaiting-changes` | A trusted reviewer asked for changes and the bounded fix rounds could not settle it. | Wait. The hub resumes when a human re-reviews or merges. |
| `parked` | Settled for a human for a reason none of the above covers. | `get_run`, then the gentlest recovery that fits. |

Only `pending` and `paused` are runnable — those are the two a drain will pick up.

## Hold gates

What `queue_status.held_gate` reports when `held` is true. The gate is what
separates a deliberate wait from a symptom; `held_reason` and `held_since` say
which instance and since when.

### Deliberate waits — do not "fix" these

| Gate | Why the drain is waiting |
| --- | --- |
| `blocked` | Every runnable row has an unresolved blocker. |
| `self-reload` | A hub self-reload is pending and waiting for hub-wide idle. |
| `repo-busy` | A serial repo (or a folder repo) already has its one run in flight. |
| `release` | An epic is releasing — merging its stack — and holds the repo while it does. |
| `publish` | A Publish session holds the repo's queue (ADR 0053). Not the same thing as `release`. |
| `branch-held` | A branch a queued item needs is checked out in another worktree. |
| `parked-epic` | An epic whose open children are all `not-ready` parked before spawning anything. It unparks itself when a child becomes pickable. |

### Symptoms — worth reading into

| Gate | What it points at |
| --- | --- |
| `queue-error` | The drain could not read or write the queue. |
| `launch-failed` | A child could not be spawned. |
| `stalled` | Synthesised after **2 minutes** in which the drain loop reached no decision at all — armed, with nothing draining it. |

The QA gate is **not** on this list. It is not a hold: it is the item status
`awaiting-qa`.

## Pause classes

How a `paused` run's reason classifies. The hub emits an **Unblock prompt** for the
first three and for quarantines and faults; `reauth` and `usage_window` get none,
because no amount of work clears them.

| Class | What happened | What clears it |
| --- | --- | --- |
| `hook_rejected` | The repo's pre-push hook refused the push, and trau's own artifact refresh and retry didn't clear it. | Fix the failing check the folded rejection names, on the run's branch. A bare re-attempt fails the same way. |
| `branch_held` | git allows a branch one worktree at a time, and the tree holding it belongs to no live run. | Confirm nothing live owns it, then free the branch — never by removing a worktree the hub owns. |
| `dialog` | The agent is standing at an interactive prompt and cannot answer it. Not a failure. | Answer it once in an interactive session of that provider, on the hub's machine — or `steer_agent kind=keys` while watching the terminal. |
| `reauth` | A provider auth wall. | The person re-authenticates. |
| `usage_window` | A provider rate or usage limit. | Time. |
| `other` | Anything else trau could not classify. | Read `held_reason` / the run reason and clear exactly what it names. |

A **forge outage** — the code host erroring or the network never reaching it —
pauses blamelessly too: the checkpoint stays where it was and the verified work is
**not** re-run when the forge comes back.

`reauth`, `usage_window` and an unreachable hub are the *blameless* pauses
`QUEUE_AUTO_RESUME` will re-attempt on a backoff. Faults never are.

## Run phases

Where a checkpoint sits. The order is stable across versions, so "earlier phase"
always means "got less far".

```
building → built → handed_off → verified → pr_open → merged
```

| Phase | Reached when |
| --- | --- |
| `building` | The build agent is working. |
| `built` | The build finished. |
| `handed_off` | The handoff brief is written. |
| `verified` | Verify passed. |
| `pr_open` | The pull request exists. Both `awaiting-merge` and `awaiting-changes` park *here* — the work reached the same place either way and only the reason for stopping differs, which the failure class carries. |
| `merged` | Landed on the base branch. |
| `quarantined` | Terminal, off the ladder: verify spent its repairs and bugfixes and parked the ticket for a human. |

`releasing` shows on an epic while its stack merges.

`list_runs` comes back in board order — earliest phase first, then ticket — so the
stuck runs lead. Neither it nor `trau forensics runs` sorts by recency: sort
client-side when the question is "what settled last".
