# GitHub Issues-specific operations

Everything goes through `gh issue` — the same `gh` CLI you're already using for PRs. No extra MCP needed.

## Fetch a ticket

```bash
gh issue view <number> --json title,body,state,assignees,labels
```

Use `title` to derive the branch description.

## Create an issue

Used when the user kicks off with no ticket id and chooses "create an issue" (SKILL.md Step 2 / `references/plan-kickoff.md`). Same `gh` CLI you already use for PRs — no extra access needed beyond `gh auth`:

```bash
gh issue create --title "<summary from the plan>" --body "<plan goal / scope / acceptance criteria>"
```

`gh issue create` prints the new issue URL; the trailing number (`…/issues/42` → `42`) is your ticket id. Feed it into branch naming per the prefix convention below (`feature/42-…` or `feature/issue-42-…`). If the project tracks "in progress" via a label, add it now (`--label`); if it uses Projects v2, add the issue to the board per the status section below. Don't `--assignee` unless the user asks — same non-self-assignment rule as the main flow.

## Update status

GitHub Issues only has two native states: `OPEN` and `CLOSED`. There's no built-in "In Progress" or "In Review". Two common workarounds — check `tracker.statuses` to see which the project uses:

### Option A: Labels

If `tracker.statuses` values look like label names (e.g. `"in-progress"`, `"in-review"`), use labels:

```bash
gh issue edit <n> --add-label "in-progress" --remove-label "ready"
gh issue edit <n> --add-label "in-review"   --remove-label "in-progress"
gh issue close <n>                          # for "done"
```

### Option B: Projects (v2)

If the repo uses GitHub Projects (v2) with a Status field, status names map to Project field options:

```bash
# Find the project & item
gh project item-list <project-number> --owner <owner> --format json
# Update the Status field
gh project item-edit --id <item-id> --field-id <status-field-id> --single-select-option-id <option-id>
```

This is more involved — if the project uses Projects v2, have the user record the relevant ids in config under `tracker.project: { number, statusFieldId, options: { inProgress, inReview, done } }` to avoid looking them up every session.

## Attach a PR URL

You don't need to. Putting `Closes #<n>` in the PR body auto-links the PR to the issue, and merging the PR auto-closes the issue. Done.

If for some reason auto-linking is undesirable, comment instead:

```bash
gh issue comment <n> --body "PR: <url>"
```

## Branch naming

GitHub Issues don't have a project prefix — the issue is just `#42`. Two conventions in common use:

- **No prefix** (issue number only): `feature/42-add-reminders`. Set `tracker.ticketPrefix` to empty string.
- **Word prefix**: `feature/issue-42-add-reminders`. Set `tracker.ticketPrefix` to `"issue"`.

Either is fine — pick what matches existing branches in the repo.

PR title format becomes `#42: add booking reminders` (or just `add booking reminders` with `Closes #42` in the body, since the title `#42:` reads oddly to some teams).
