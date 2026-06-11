# Jira-specific operations

Jira interaction goes through either an Atlassian MCP server (if loaded in the session) or the Jira Cloud REST API via curl. Check what's available first; prefer MCP when present because auth is handled.

REST examples below assume Jira Cloud REST API v3 with basic-auth header `-u email:API_TOKEN` or a Bearer token.

## Capability check (do this first, every session)

Before assuming you can read or transition a Jira ticket, verify access. **`tracker.type: "jira"` only tells you the *project* uses Jira — it does not guarantee you can talk to it.**

Check, in this order, and stop at the first match:

1. **Atlassian MCP with issue-management tools loaded.** Look for tools whose names contain `get_issue`, `transitions`, `update_issue`, `add_comment` (under any `*Atlassian*`, `*jira*`, or `*Rovo*` prefix). Auth-only tools (`*authenticate`, `*complete_authentication`) **do not count** — they let you log in but expose no issue operations on their own.
2. **REST credentials in env.** `JIRA_BASE_URL` + (`JIRA_EMAIL` + `JIRA_API_TOKEN`) or `JIRA_BEARER_TOKEN`. If set, a `curl` against `GET /rest/api/3/myself` should return 200.
3. **`tracker.statusManagement: "skip"` in config** (see SKILL.md schema). Treat this as an explicit "I know, don't try."

If **none** of the above succeed: ticket management is **not possible** in this session.

### Degraded mode — what to do when ticket management is not possible

- **Tell the user once**, concisely, on the first PR/branch action of the session: *"No Jira API access in this session — branch/PR work will proceed, but ticket status transitions and comment-back-with-PR-url will be skipped. Set credentials or `tracker.statusManagement: \"skip\"` in `.dev-flow/config.json` to silence this notice."* Do not re-warn for every subsequent action.
- **Use the ticket id for naming only** — branch name, commit `Refs:` trailer, and PR title prefix still happen because they don't need API access.
- **Skip** every step in this file that requires a network call: ticket fetch, transitions, PR-URL comment.
- **Do not invent ticket summaries**. If you can't fetch the ticket, ask the user for a one-line description to use in the branch name.
- **Do not retry** or attempt fallback API hosts — fail closed, keep moving.

## Fetch a ticket

```
GET /rest/api/3/issue/<TICKET-ID>
```

Returns `fields.summary`, `fields.status`, `fields.assignee`, `fields.description`. Use `summary` to derive the branch description.

## Detect a parent (epic)

Modern Jira (both team-managed and company-managed projects) exposes the parent uniformly:

```
GET /rest/api/3/issue/<TICKET-ID>?fields=parent,summary
```

`fields.parent.key` is the parent's id (e.g. `MLG-190`) — that's the epic for SKILL.md Step 2.5; `fields.parent.fields.summary` names the epic branch if one needs bootstrapping. Via MCP, the same `parent` field appears in the get-issue response. Two caveats:

- **Legacy "Epic Link"**: very old company-managed setups store the epic in a custom field (`customfield_1xxxx`) instead of `parent`. If the issue type suggests it belongs to an epic but `parent` is empty, ask the user rather than hunting custom fields.
- **Degraded mode** (no API access per the capability check): ask the user whether the ticket belongs to an epic and which one.

## Create an issue

Used when the user kicks off with no ticket id and chooses "create an issue" (SKILL.md Step 2 / `references/plan-kickoff.md`). Creating needs the same API access as transitions — only offer it when the capability check above passed.

**Via Atlassian MCP** (preferred — auth handled): use the create-issue tool (name contains `createJiraIssue` / `create_issue`). Pass the configured project key, an issue type (default `Task` unless the user names another), the summary, and a description built from the plan. MCP tools generally accept markdown/plain text for the description.

**Via REST** (note: v3 wants the description in Atlassian Document Format, not a raw string):

```
POST /rest/api/3/issue
{
  "fields": {
    "project":   { "key": "<tracker.project>" },
    "issuetype": { "name": "Task" },
    "summary":   "<one-line summary from the plan>",
    "description": {
      "type": "doc", "version": 1,
      "content": [{ "type": "paragraph",
        "content": [{ "type": "text", "text": "<plan goal / scope / acceptance criteria>" }] }]
    }
  }
}
```

Returns `{ "key": "<PROJECT>-<n>" }` — that key is the ticket id for branch/commit/PR naming. Scope creation to `tracker.project`; never open into a different project without confirming. A newly created issue sits in its workflow's default status — move it to `tracker.statuses.inProgress` via the transition flow below as part of Step 4.

## Update status (use transitions, not direct writes)

Jira does not let you `PUT` a new status directly — you go through a *transition* whose target is the status you want. The flow:

1. List available transitions:

   ```
   GET /rest/api/3/issue/<TICKET-ID>/transitions
   ```

   Returns an array of `{ id, name, to: { name } }`.

2. Find the transition where `to.name` matches `tracker.statuses.inProgress` (or whichever you need). Transition *names* are workflow-specific ("Start Progress", "Move to Doing", "Begin work" — all real examples).

3. Execute the transition:

   ```
   POST /rest/api/3/issue/<TICKET-ID>/transitions
   { "transition": { "id": "<id>" } }
   ```

Don't hard-code transition ids — they vary per project workflow. Look them up each session, or have the user record them in config under a `tracker.transitions` map if they're stable.

## Attach a PR URL

If the **Jira ↔ GitHub integration** (the official "GitHub for Jira" app) is enabled in the workspace:
- Including the ticket id in the **PR title** (e.g. `PROJ-42: fix login redirect`) or **branch name** (already covered by branch-naming convention) is enough — the integration auto-links the PR to the issue and surfaces it in the "Development" panel.
- No separate API call needed.

If the integration is **not** enabled:
- POST a comment with the PR URL: `POST /rest/api/3/issue/<TICKET-ID>/comment` with `{ "body": "PR: <url>" }`.

If unsure whether the integration is enabled, ask the user once and stash the answer in config (e.g. `tracker.devIntegration: "github"`).

## Multi-prefix repos

Jira projects often coexist in one repo (`PROJ`, `BACK`, `INFRA`). If the project uses multiple prefixes:
- Set `tracker.ticketPrefix` to the most common one (used as default expansion for bare numbers).
- Set `tracker.ticketIdPattern` to a regex covering all valid prefixes, e.g. `^(PROJ|BACK|INFRA)-\\d+$`.
- When the user types a bare number, ask which project it belongs to rather than guessing.
