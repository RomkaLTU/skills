# Linear-specific operations

These map to the Linear MCP tools (`mcp__claude_ai_Linear__*`).

## Fallback when Linear MCP is unavailable or misconfigured

The MCP isn't always loaded — sessions can start without it, the wrong workspace might be selected, or auth might lapse. **Don't block the workflow on tracker access.** Instead, fall back to manual-tracker behavior automatically:

1. **Detect the issue early.** On the first tracker call (Step 2 fetch), if `mcp__claude_ai_Linear__get_issue` is missing, returns an auth error, or returns a ticket from the wrong workspace (`team` doesn't match `tracker.team`), surface a one-line warning to the user and switch to fallback mode for the rest of the session.

2. **Surface a clear warning once:**

   > "⚠️ Linear MCP unavailable (or wrong workspace). Falling back to manual reminders for tracker steps. Update Linear by hand and I'll keep going."

3. **From that point forward, treat it like `tracker.type: "manual"`** for the *tracker-side* operations only:
   - **Step 2 (fetch):** ask the user for the ticket title inline, cache to `.dev-flow/tickets/<TICKET-ID>.json` per `references/manual-tracker.md` so we don't keep asking.
   - **Step 4 (move to In Progress):** render a reminder ("Mark `MLG-123` as **In Progress** in Linear").
   - **Step 8 (move to In Review + attach PR):** render a reminder with the PR URL.
   - **Step 9 (move to Done):** render a reminder.

4. **Don't switch the config.** This is a session-scoped runtime fallback — the project still has `tracker.type: "linear"` in its config; we're just adapting because the MCP isn't available *right now*. Next session, if Linear MCP is back, the skill resumes automatic updates without any config edits.

5. **Don't try Linear's REST API as a backup.** Auth differs per workspace (OAuth vs API keys), rate limits and scopes vary, and probing for credentials is intrusive. Reminders are more reliable than half-working automation.

## Scope every call to the configured project & team

## Scope every call to the configured project & team

When listing or searching tickets, always pass:

```
project: <tracker.project>
team:    <tracker.team>
```

Never operate against an unrelated Linear project from this repo. If the user pastes a ticket id from a different project (e.g. they reference a ticket from a sister product), confirm before doing any writes — don't silently update someone else's ticket because the id parsed cleanly.

## Fetch a ticket

```
mcp__claude_ai_Linear__get_issue
  id: "<TICKET-ID>"
```

Use the returned `title` to derive the branch description and PR title.

## Update status

```
mcp__claude_ai_Linear__save_issue
  id:    "<TICKET-ID>"
  state: { name: "<status name>" }
```

Status names come straight from `tracker.statuses.{inProgress|inReview|done}`. Linear is case- and exact-match sensitive — if the workspace uses "In progress" (lowercase p) the call fails on "In Progress". When in doubt, fetch the issue once and inspect the available state names on its team.

## Attach a PR URL

After opening the PR, **prefer** the attachment API — it surfaces in the Linear UI as a first-class link with the PR's status:

```
mcp__claude_ai_Linear__create_attachment
  issueId: "<TICKET-ID>"
  url:     "<pr url>"
  title:   "PR #<n>: <summary>"
```

**Fallback** if attachments aren't available: post a comment on the issue with the PR URL. Linear will still auto-detect and link it, just without the rich preview.

## Create an issue

Also reached from plan-kickoff when the user has no ticket id and chooses "create an issue" (SKILL.md Step 2 / `references/plan-kickoff.md`).

```
mcp__claude_ai_Linear__save_issue
  team:        "<tracker.team>"
  project:     "<tracker.project>"
  title:       "<summary from the plan>"
  description: "<plan goal / scope / acceptance criteria — markdown>"
```

`save_issue` without an `id` creates; the response carries the new `<TEAM>-<n>` identifier, which becomes the ticket id for branch/commit/PR naming. In plan-kickoff the plan supplies the title and description; otherwise ask for a one-line title. Always set `team` and `project` to the configured values, and reject (with a confirmation prompt) any request that would create or move a ticket into a different project — this prevents the common slip of opening a ticket against the wrong product when working across multiple Linear-tracked codebases. After creating, move the new issue to `tracker.statuses.inProgress` as part of Step 4.

## Branch-name expansion

Linear ticket ids are always `<TEAM>-<n>`. If the user types a bare number, expand it using `tracker.ticketPrefix` (which usually equals `tracker.team`).
