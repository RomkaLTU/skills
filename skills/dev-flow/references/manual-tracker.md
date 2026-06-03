# Manual tracker

When `tracker.type: "manual"`, the project has tickets but the assistant can't reach them programmatically — the tracker might be offline, an internal tool with no API, paper, or just "we use a Notion table". The user supplies ticket info inline; the skill stores it locally so it doesn't ask twice and so PR/commit/time-tracking output stays consistent.

## Where ticket data lives

```
.dev-flow/tickets/<TICKET-ID>.json
```

The skill must ensure `.dev-flow/tickets/` is in `.gitignore` before writing the first ticket (same gitignore enforcement pattern as time tracking). One developer's local notes about a ticket shouldn't enter git history or affect coworkers.

```bash
grep -qxF '.dev-flow/tickets/' .gitignore 2>/dev/null \
  || echo '.dev-flow/tickets/' >> .gitignore
```

## Schema

```json
{
  "id": "TASK-42",
  "title": "Add booking reminders",
  "description": "Optional longer context — pasted from the offline tracker",
  "url": null,
  "createdAt": "2025-11-04T10:00:00Z"
}
```

`url` is optional. If the user has a deep-link to the ticket in their tool, store it — the skill includes it in PR drafts and time-tracking output for traceability.

## Creating a ticket during plan-kickoff

When the user kicks off from a plan with no ticket id and chooses "create an issue" (SKILL.md Step 2 / `references/plan-kickoff.md`), there's no remote API to call — "create" means recording a local ticket:

1. **Mint an id.** Use `tracker.ticketPrefix` + the next free number — scan `.dev-flow/tickets/<PREFIX>-*.json` for the highest existing number and add one (e.g. existing `TASK-7` → new `TASK-8`). If no prefix is configured, ask the user what to call it.
2. **Write the file** at `.dev-flow/tickets/<id>.json` with `title` and `description` taken from the plan (after ensuring the gitignore entry above). `url` stays null.
3. Use the new id for branch/commit/PR naming exactly like a user-supplied one.

This keeps offline-tracked projects consistent: the plan becomes the ticket's recorded description, so PR drafts and time-tracking output have something real to reference.

## Workflow contract

### Step 2 — Require a ticket

When the user says "let's start work on `TASK-42`":

1. Look in `.dev-flow/tickets/TASK-42.json`. If found, use the title and description.
2. If not found, ask:
   > "I don't have details for `TASK-42`. What's the title?
   > Optional: short description, URL if you have one."
3. Save the answer to the file. Use the title to derive the kebab branch description and the PR title.

### Step 4 — Move to In Progress

The assistant can't update the offline tracker. Render a reminder:

> "Don't forget to mark `TASK-42` as **In Progress** in your tracker."

Don't block on it — just remind once.

### Step 8 — Move to In Review, attach PR

Same — remind:

> "Mark `TASK-42` as **In Review** in your tracker, and attach this PR URL: `<url>`"

If the local ticket file has a `url`, include it in the PR body for the reviewer's traceability.

### Step 9 — Move to Done

After merge confirmation:

> "Mark `TASK-42` as **Done** in your tracker."

Then update local `.dev-flow/tickets/TASK-42.json` with `completedAt: <now>` so future "list my tickets" queries can distinguish open vs closed.

## Listing local tickets

If the user asks "what tickets do I have locally?", list `.dev-flow/tickets/*.json` showing id, title, status (open/completed), `createdAt`. Useful when picking up paused work or auditing what was done in a sprint.

## Multi-prefix repos

If the project has more than one ticket source/prefix (rare for manual-tracker repos but possible), set `tracker.ticketIdPattern` to a regex covering all valid prefixes, e.g. `^(TASK|BUG|STORY)-\\d+$`.
