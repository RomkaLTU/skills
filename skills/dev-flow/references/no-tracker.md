# No tracker

When `tracker.type` is `"none"`, or the user has explicitly opted out of ticket tracking for a single change, the workflow simplifies — but doesn't disappear. The branch/PR discipline still matters because reviewers still need to find the right base and a clean diff.

## What changes

- **Branch naming**: drop the ticket id segment. Format becomes `<type>/<short-kebab-description>` (e.g. `fix/login-redirect-loop`).
- **Commit messages**: same conventions as before; just no `Refs:` trailer.
- **PR title**: just the summary (no `<TICKET-ID>: ` prefix). Keep under 70 chars.
- **PR body**: same `## Summary` and `## Test plan` sections. Drop the `Closes <TICKET-ID>` line.

## What stays the same

- Branch off the base branch, sync first.
- `gh pr create --base <baseBranch>` is **still mandatory** — the silent default-branch trap is independent of ticket tracking.
- Verify base + commit count after PR creation.
- Don't merge yourself.

## Steps to skip

- Step 4 (move to In Progress) — no tracker, no status to update.
- Step 7 (move to In Review + attach PR) — same reason.
- Step 8 collapses to: wait for merge confirmation, sync base, delete branch.

## When to push back

This mode is fine for personal repos and very small one-off fixes. For team work, push back gently — even a one-line "track this in our issue tool" ticket is worth more than no ticket, because it gives future-you something to grep for when the customer reports the same thing six months later.
