# Time tracking

Track time on tickets as if a senior human developer did the work. This is for client billing, internal effort tracking, and feeding into time-tracking tools (Linear's time field, Jira worklogs, Toggl, Harvest, Clockify, etc.).

The assistant is *not* logging its own wall-clock time — it's estimating realistic human effort.

## When this happens in the workflow

Time tracking hooks into the existing steps. There's no separate "log time" invocation — it happens at natural boundaries:

- **Step 4** (move ticket to In Progress) — create/open the time file, set the `started` timestamp.
- **After Step 8** (PR opened, ticket moved to In Review) — estimate effort for the work since the last logged entry and append it as a *provisional* entry (`"confirmed": false`). Don't ask the user to confirm the number here.
- **Step 9** (close-out) — confirm the accumulated total with the user, mark the entries confirmed, render the consolidated copy-paste output, set `completed`.

If the user requests changes after PR review:
- Treat the work between "user asks for changes" and "next push to the PR" as a new entry.
- Append it. Total accumulates. Same flow at the next "ready for review" moment.

**Close-out means accepted, not merged.** Where the project has a QA stage between merge and Done — the ticket parks in "Ready for QA" rather than closing on merge — wait for QA sign-off before asking. QA sending the ticket back is more work, which is another entry; confirming at merge would close a total that hasn't stopped moving.

## Where data lives

**Default — per-repo, per-ticket:**

```
.dev-flow/time/<TICKET-ID>.json
```

The skill **must** ensure `.dev-flow/time/` is in `.gitignore` before writing the first entry. This is non-negotiable: time data is per-developer (different people work at different paces) and often sensitive (effort numbers feed billing). It must not enter git history or get clobbered by another developer's commits.

To add it cleanly:

```bash
# If .gitignore exists and doesn't already contain the line, append it
grep -qxF '.dev-flow/time/' .gitignore 2>/dev/null \
  || echo '.dev-flow/time/' >> .gitignore
```

Note: the dev-flow config file (`.dev-flow/config.json`) is *not* gitignored — that's project setup and should be committed. Only the `time/` subdirectory is excluded.

**Override via config:**

- `timeTracking.storage: "user"` → stored at `~/.dev-flow/time/<repo-slug>/<TICKET-ID>.json`. Use this if you don't want any time-tracking artifacts inside the repo at all (e.g., if `.gitignore` is owned by a strict CI process you can't modify, or you work across many machines and want everything in one place). `<repo-slug>` derived from `git config --get remote.origin.url`; falls back to the repo basename.
- `timeTracking.storage: "none"` → don't persist; produce the output at close-out only and forget it after the session.

## File schema

```json
{
  "ticketId": "MLG-123",
  "ticketTitle": "Add booking reminders",
  "branch": "feature/MLG-123-add-booking-reminders",
  "started": "2025-11-04T10:00:00Z",
  "completed": null,
  "entries": [
    {
      "date": "2025-11-04",
      "minutes": 195,
      "summary": "Initial implementation: scaffold reminder service, wire to existing notification queue, add unit tests",
      "diffStats": { "files": 8, "additions": 234, "deletions": 12 },
      "commits": ["a1b2c3d", "e4f5g6h"],
      "confirmed": false
    }
  ],
  "totalMinutes": 195
}
```

`confirmed` starts `false` on every appended entry and flips to `true` for all entries at close-out, once the user agrees the total. `completed` gets set at the same moment. `totalMinutes` is recomputed every time an entry is appended (sum of `entries[].minutes`).

## Estimating effort

Estimate what a senior developer would realistically take, including:

- Investigation (reading existing code, understanding context)
- Actual implementation
- Writing/updating tests
- Manual verification
- Reasonable Slack/PR-comment chatter
- *Not* including full deep-dive learning of an unfamiliar tech stack (that's outside the ticket scope)

### Anchors (starting points, not rules)

| Change shape | Senior dev range |
|---|---|
| Config tweak / typo / one-line fix | 15–30 min |
| Small bug fix, single file, <50 lines, no new tests | 30–60 min |
| Bug fix with tests, 2–4 files | 1–2 h |
| Small feature, single component or endpoint, with tests | 2–4 h |
| Feature spanning UI + API + DB | 4–8 h |
| Mechanical refactor touching many files | 2–4 h |
| Architectural change with deep design work | 1–3 days |

Anchor against diff size, file count, distinct concerns touched, and ticket complexity. A 200-line diff that's mostly generated migration scaffolding ≠ a 200-line diff that rewrites a state machine.

### Confirm once, at close-out

Estimates are recorded as work happens and confirmed **once**, when the ticket is accepted — not each time a PR opens. A number confirmed at PR time is premature: review comments and QA findings both add work, and re-litigating the total after every round wastes the user's attention on a figure that is still moving.

So: append each round's entry provisionally and say nothing about confirming it. At close-out, present the accumulated total and let the user adjust:

> "MLG-123 is done. I logged 2 rounds totalling 4h 30m (initial implementation 3h 15m, review fixes 1h 15m). Confirm, or give me a different number?"

The user knows their pace and the political weight of the number better than the skill does. Don't mark anything confirmed without an explicit answer. If they just say "yes", proceed; if they give a different number, use theirs without re-arguing — and if they restate the whole total rather than per-entry, scale the entries to match or record it as one adjusted total, whichever they asked for.

## Computing the diff for an entry

To estimate work in a round:

```bash
# Everything since the branch diverged from base
git diff --stat <baseBranch>...HEAD

# Or just the new commits since the last logged entry
git log --oneline <last-entry-last-commit-sha>..HEAD
git diff --stat <last-entry-last-commit-sha>..HEAD
```

Capture file count, lines added/removed, and the new commit shas → these populate `diffStats` and `commits` in the entry, and inform both the estimate and the entry `summary`.

## Output formats

Once the user has confirmed the total at close-out, render a copy-paste block in whatever format the project's `timeTracking.outputFormat` requests.

### `default` (human-readable)

```
[MLG-123] Add booking reminders
Branch: feature/MLG-123-add-booking-reminders
Total: 4h 30m

Sessions:
- 2025-11-04 (3h 15m) — Initial implementation: scaffold reminder service, wire to existing notification queue, add unit tests
- 2025-11-05 (1h 15m) — Follow-up: handle DST edge case, update test fixtures
```

### `jira-worklog`

One block per entry — paste into Jira's "Log work" dialog:

```
MLG-123 — 2025-11-04 — 3h 15m
Initial implementation: scaffold reminder service, wire to existing notification queue, add unit tests

MLG-123 — 2025-11-05 — 1h 15m
Follow-up: handle DST edge case, update test fixtures
```

### `toggl-csv` (works for Harvest, Clockify, most CSV importers)

```
ticket,date,duration_minutes,description
MLG-123,2025-11-04,195,"Initial implementation: scaffold reminder service, wire to existing notification queue, add unit tests"
MLG-123,2025-11-05,75,"Follow-up: handle DST edge case, update test fixtures"
```

### `plain`

```
MLG-123 — 4h 30m total — Add booking reminders
```

If the user asks for a different format on the spot, render that too — the underlying file has all the data.

## When to skip time tracking entirely

- `timeTracking.enabled: false` in config → skip every step.
- `tracker.type: "none"` → skip by default (no ticket to bill against). Override with explicit `timeTracking.enabled: true` if the user wants free-form time entries anyway.
- One-line typo fixes with `requireTicket: false` exceptions → ask the user whether to bother; default no.
