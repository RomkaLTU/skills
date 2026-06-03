---
name: dev-flow
version: 1.0.0
description: Run a project's ticket-driven git workflow end-to-end — branch from the base branch, tie every branch to a project-management ticket (Linear, Jira, GitHub Issues, or none), name branches and commits correctly, open the PR against the right base with verification, and move the ticket through In Progress / In Review / Done. Also kicks off work from an execution plan: hand it a plan file (e.g. `tasks/<branch>/todo.md`), a spec/PRD, or pasted plan text and it resolves a single ticket (one you give, one it offers to create in the tracker, or ticket-free after you confirm), then creates the branch and starts the work. Use whenever the user wants to start work on a ticket (by id or bare number), kick off a branch from a plan / spec / PRD / todo file, open a PR for a feature or fix, sync ticket status with branch state (e.g. close out after a merge), or asks "what branch should I use?" — even if they don't mention git, branches, or PRs. Also use it to set up or reconfigure THIS skill's own config at `.dev-flow/config.json` (the tracker, base branch, and PR / commit / time-tracking settings): when that file is missing it runs an auto-detecting setup wizard before starting work, and it handles explicit "set up the ticket flow / dev-flow config" or "change the base branch / tracker" requests. Don't use it for reviewing an existing PR's code, a one-off commit on a branch you've already created, breaking a plan into many separate issues, writing a PRD, configuring CI / GitHub Actions workflows, promoting one long-lived branch into another (a release or integration merge between standing branches), or general git how-to questions — those belong to other tools.
---

# Dev Flow — ticket-driven git workflow

## Why this exists

Keeping branches, commits, PRs, and the project-management ticket aligned across a team is one of those things that's "obvious" until two people forget it on the same day — and now `main` has a half-merged feature, no ticket got moved to Done, and the PR was accidentally opened against a stale base branch with 47 unrelated commits dragged along. This skill bakes that alignment into a checklist that runs end-to-end.

The promise: when the user says "let's start work on ticket X" (or "PR this thing"), do the ceremony correctly without being asked twice — pick the right base, name the branch right, sync the tracker, and remember the things that have actually broken in real projects (like `gh pr create` silently picking a non-`main` default base).

## Step 0 — Load the project's dev-flow config

Before anything else, find the project's config. Look in this order and stop at the first match:

1. `.dev-flow/config.json` in the repo root
2. A "Ticket Flow Config" JSON code block inside `CLAUDE.md` or `AGENTS.md`
3. Nothing found — **the project isn't set up yet, so initialize it before going further.** This skill owns its own setup; there's no separate command to hand off to. Read `references/setup-wizard.md` and walk the wizard inline: it auto-detects what it can (git host, `gh` CLI, existing commit skill, tracker MCP), asks only what it can't, confirms the assembled config, and writes `.dev-flow/config.json`. Because it's mostly auto-detected and confirms before writing, run it rather than blocking the user — a one-line "no dev-flow config here yet, let me set it up" and then proceed. Two ways in land here: the user explicitly asked to set up / configure the flow, or they asked to start work and there's simply no config yet. **Fallback:** if the user only wants a one-off and not full setup, ask the minimum questions inline and proceed for this branch without writing a config file.

### Schema

All fields optional except `tracker.type`. Sensible defaults are noted.

```json
{
  "tracker": {
    "type": "linear",                       // "linear" | "jira" | "github-issues" | "manual" | "none"
    "team": "MLG",                          // tracker-specific scope (linear/jira/github-issues)
    "project": "MLG",                       // tracker-specific scope
    "ticketPrefix": "MLG",                  // used to expand bare numbers and validate ids
    "ticketIdPattern": "^MLG-\\d+$",        // regex to validate full ids; optional
    "statuses": {
      "inProgress": "In Progress",
      "inReview":   "In Review",
      "done":       "Done"
    },
    "statusManagement": "auto"               // "auto" (default) = transition statuses when API access exists
                                             // "skip" = never transition; ticket id is used for branch/PR naming only
                                             // Set to "skip" for trackers (e.g. Jira) where the session has no API access
                                             // to avoid repeated capability-check warnings.
  },
  "git": {
    "baseBranch": "main",                   // default: "main"
    "remote":     "origin",                 // default: "origin"
    "branchPrefixes": {                     // override only if your team uses different verbs
      "feature":  "feature",
      "fix":      "fix",
      "chore":    "chore",
      "refactor": "refactor"
    }
  },
  "pullRequest": {
    "automation": "gh",                     // "gh" = use GitHub CLI; "manual" = render a copy-paste draft
    "reviewers": [
      { "email": "person@example.com", "githubHandle": "alice" }
    ],
    "skipSelfReview": true                  // GitHub disallows self-review; respect that
  },
  "commitSkill": {
    "name": "commit",                       // the project's commit slash-command, if any
  },
  "requireTicket": true,                    // false = allow no-ticket branches by default
  "skillSelection": {
    "askBeforeImplementation": true         // false = skip the skill-picker prompt
  },
  "timeTracking": {
    "enabled": true,                        // false to skip every time-tracking step
    "outputFormat": "default",              // "default" | "jira-worklog" | "toggl-csv" | "plain"
    "storage": "repo"                       // "repo" (default, gitignored) | "user" | "none"
  }
}
```

Once loaded, hold these values in your head for the rest of the session — they drive every decision below.

See `assets/example-config.json` for a fully filled-out example.

## Step 0.5 — Plan-kickoff mode (optional entry point)

This skill has two front doors. The everyday one is "start work on `TICKET-ID`" — you already have a ticket and want the ceremony done right. The other is **plan-kickoff**: the user hands you an execution plan (often the output of a planning or grilling session) and wants it turned into a branch with work underway. This is the bridge from "we decided what to build" to "the work is started", so plan-kickoff *creates the branch* as part of the kickoff instead of waiting to be asked separately.

### Recognize the entry

Read what the user passed — a slash-command argument or something referenced inline in their message — and route by its content. No special flag is needed:

| Input | Treat as |
|-------|----------|
| A path that resolves to an existing file (e.g. `tasks/feat-x/todo.md`, `docs/plan.md`) | **plan file** — read it, remember the path |
| Text matching `tracker.ticketIdPattern` (e.g. `MLG-42`), or a bare number when config has a single `ticketPrefix` | **ticket id** — the normal flow; skip plan-kickoff |
| Substantial free-form prose describing work to do (multi-sentence, not a path, not a ticket id) | **inline plan** — capture the text verbatim |
| Nothing | normal flow — fall through to Step 2 and ask for a ticket |

When you can't cleanly tell an inline plan from a ticket reference, ask one quick disambiguating question rather than guessing — a misread here sends the whole flow down the wrong path.

### What plan-kickoff does

1. **Capture the plan.** For a file, read it and keep the path (you'll reference it again at PR time). For inline text, hold the text. Either way, extract a one-line **summary**, the change **type** (`feature` / `fix` / `chore` / `refactor` — infer from the plan's framing or a `tasks/<type>-…` path segment; ask only if genuinely unclear), and a 3–6 word **kebab description** for the branch.
2. **Resolve the ticket *before* creating the branch** — this is the double-check. Go to Step 2; in plan-kickoff the no-ticket case surfaces the create-an-issue offer described there.
3. **Create the branch** (Step 3) using the plan-derived type + description.
4. **Continue the normal flow** — In Progress (Step 4), the skill-selection prompt (Step 5), then implement *following the plan*. The plan is both your implementation guide and the source for the PR at Step 7.

The detailed contract — argument parsing, deriving names, and how the plan feeds the created issue and the PR — lives in `references/plan-kickoff.md`. Read it when you enter this mode.

## Escape hatch — ad-hoc fixes on the current branch

Not every change wants a ticket and a fresh branch. When the user explicitly asks for a small fix on whatever branch is already checked out, honor that instead of running Steps 1–9 — refusing a one-line change because there's no ticket, or because the branch has unrelated WIP, costs more than the traceability it buys. Check `adHocFixes` in the config loaded at Step 0:

- `adHocFixes.allowed` falsey or absent → no escape hatch; run the normal flow and resolve a ticket per Step 2.
- `adHocFixes.allowed: true` → ad-hoc mode is available, but **only when the user opts in for a specific change.** Recognize the intent behind signals like "quick fix", "just fix/edit this here", "on this branch", "no ticket", "don't branch", "hotfix here", "skip the workflow" — read meaning, not exact words. The opt-in is per-request; the next unrelated request returns to the default flow.

How far it relaxes follows `adHocFixes.scope` (`edit-commit-push` = full bypass; `edit-and-commit` = stop before push; `edit` = edits only):

- **Edit** files on the current branch — Steps 1 (branch) and 2 (ticket) are skipped.
- **Commit** directly when asked: a plain commit, no ticket reference, skipping the configured commit skill (it expects a ticket). Keep the project's commit-message conventions and stage files by name.
- **Push** the branch when asked, if scope permits and `adHocFixes.confirmBeforePushOrPr` is false — no PR, no Step 7/8 status sync. If that flag is true, pause before pushing or opening a PR.

Floor that holds regardless of scope:

- **Never commit or push to the base branch** (`git.baseBranch`). With `adHocFixes.neverOnBaseBranch: true`, if base is checked out, offer a short ticket-free branch (e.g. `fix/<short-description>`) and work there. Editing base is fine; committing/pushing it is not.
- **Don't absorb unrelated WIP.** Stage only the files your fix touched (never `git add -A` / `git add .`) and tell the user the change rides along with this branch.
- If an ad-hoc change does become a PR, the Step 7 `--base` verification is still worth running — wrong-base PRs have a way of dragging in dozens of unrelated commits.
- No force-push, no committing secrets, no `--no-verify`.

## Step 1 — Always branch from the base branch

Throughout this skill, `<baseBranch>` refers to `git.baseBranch` from config (default `main`; some teams set it to an integration branch like `dev` or `develop`). Substitute the literal value when running commands.

Never start coding on the base branch. Two reasons:
- Direct commits to it skip review and break the audit trail.
- Branching from a stale base produces PRs littered with already-merged commits — confusing for reviewers and risky to revert.

> **One base branch, whatever it's called.** This skill always branches from — and targets per-ticket PRs back to — whatever `git.baseBranch` is set to. For most projects that's `main`: branch off `main`, PR back to `main`, done. Some teams keep two long-lived branches (an integration branch where features land, often `dev`/`develop`, plus a production branch like `main`); there, set `git.baseBranch` to the integration branch and per-ticket PRs target it. Either way, **promoting one long-lived branch into another** (a release or integration merge between standing branches) is **out of scope** — the user opens that PR by hand when they're ready to ship.

Procedure:

```bash
git status
git rev-parse --abbrev-ref HEAD
```

If on the base branch with no uncommitted changes, sync and branch:

```bash
git checkout <baseBranch> && git pull --ff-only origin <baseBranch>
```

If on the base branch *with* uncommitted changes: `git stash`, branch off, then `git stash pop` on the new branch. Don't lose the user's in-progress work.

If already on a feature branch, ask the user whether to continue there or to start a new one off a fresh base.

## Step 2 — Require a ticket before coding

Every branch ties to a ticket. This is the link between "what was built" and "why we built it" — search for the ticket six months later and you can find the conversation, the customer report, the design discussion.

If the user hasn't given you a ticket id, ask. Don't invent one.

**Acceptable input forms:**
- Full id (e.g. `MLG-42`, `BACK-117`)
- Bare number (e.g. `42`) — expand to `<ticketPrefix>-<n>` if config has a single `ticketPrefix`. If config has `ticketIdPattern`, validate the resulting id matches.

**No ticket id? Resolve it before branching — present the choice, don't silently default.** When `requireTicket: true`, quietly skipping the ticket defeats the point of the flag, so offer the options explicitly (this is the double-check plan-kickoff relies on):

1. **Provide an id** — the user pastes one; validate it against `tracker.ticketIdPattern` and proceed.
2. **Create an issue now** — offer this when the tracker can create issues (`linear` / `jira` / `github-issues`, and the capability check in `references/<tracker>.md` reports API access). Build it from what you know: in plan-kickoff the plan supplies the title and body; otherwise ask for a one-line title. The returned id becomes the ticket for branch/commit/PR naming, and you then move it to In Progress at Step 4. See the **"Create an issue"** section of `references/<tracker>.md`.
3. **Proceed without a ticket** — an explicit no-ticket exception the user confirms. Treat as `tracker.type: "none"` for this branch (no id segment in the branch name, no `Refs:` trailer, status steps skipped). Fine for a typo fix or personal repo; for team work, nudge gently toward option 2.

For `tracker.type: "manual"`, "create an issue" means recording a *local* ticket — generate an id and store the plan as its description per `references/manual-tracker.md`; there's no remote API to call. For `tracker.type: "none"`, skip straight to option 3; there's nothing to create.

Default posture: with `requireTicket: true`, lead with options 1–2 and treat 3 as the deliberate override; with `requireTicket: false`, option 3 is a fine default.

Once you have a valid id, fetch the ticket via the tracker reference for your `tracker.type` (see [Reference files](#reference-files)) so you can confirm it exists and read the description. The description usually gives you the right wording for the branch name and PR title.

## Step 3 — Branch naming

Format:

```
<type>/<TICKET-ID>-<short-kebab-description>
```

Where:
- `<type>` is one of `git.branchPrefixes` keys (`feature`, `fix`, `chore`, `refactor`).
- `<TICKET-ID>` is the full id.
- `<short-kebab-description>` is 3–6 lowercase kebab-case words derived from the ticket title.

**Examples:**

- `feature/MLG-123-add-booking-reminders`
- `fix/PROJ-42-login-redirect-loop`
- `chore/INFRA-7-bump-node-version`

Create with:

```bash
git checkout -b <type>/<TICKET-ID>-<description> <baseBranch>
```

When `tracker.type: "none"`, drop the ticket id segment: `fix/login-redirect-loop`.

## Step 4 — Move the ticket to "In Progress"

As soon as the branch exists and you're starting implementation, move the ticket to `tracker.statuses.inProgress`. The tracker-specific calls live in `references/<tracker>.md`.

**Skip this step silently** when any of the following holds — branch and PR work still proceed normally:
- `tracker.statusManagement` is `"skip"`.
- The tracker-specific capability check (in `references/<tracker>.md`) reports no API access (e.g. Jira configured but no MCP issue-management tools and no `JIRA_*` env credentials).

The same skip applies to Step 8 (move to In Review) and Step 9 (move to Done).

**Don't self-assign.** If the ticket is unassigned, leave assignment to the user — they may be doing the work, or they may have delegated it to you while keeping the ticket on themselves.

→ **Time tracking:** if `timeTracking.enabled`, create or open the ticket's time file and set/update the `started` timestamp. See `references/time-tracking.md`.

## Step 5 — Pick skills to load for this task

Before any implementation begins, pause and ask the user which of the available skills should be loaded for this work. Different tickets benefit from different specialists — `vue` for SFC work, `nuxt` for routing/middleware, `laravel-simplifier` for PHP cleanup, `claude-api` for Anthropic SDK code, `simplify` for general code-quality review, etc.

This is an explicit pause on purpose. The user knows the ticket better than the skill list does, and skills brought into context cost tokens — load too many and the session gets noisy; load too few and the implementation phase misses domain-specific guidance.

Skip this step entirely if `skillSelection.askBeforeImplementation: false` in config, or if the user's prompt already named the skills to use.

### Procedure

1. **Enumerate available skills.** Skills appear in the session's `<system-reminder>` messages with names and descriptions. Build the list from there — don't guess from training data.

2. **Suggest a default selection** based on the ticket title/description and the parts of the codebase the work likely touches. Be concrete: 1–3 strong matches, not a full inventory. Explain *why* in one phrase per suggestion.

3. **Ask the user.** Use `AskUserQuestion` for a proper multi-select if available — that's the cleanest UI. Fallback: a numbered list with a comma-separated reply.

   ```
   Which skills should I load for MLG-123 (Add booking reminders)?

   Suggested: nuxt, vue
     - nuxt → reminder dispatch likely lives in server/api routes
     - vue   → user-facing reminder settings need an SFC

   All available:
     1. vue
     2. nuxt
     3. laravel-simplifier
     4. simplify
     5. claude-api
     6. vercel:shadcn
     ...

   Reply with names (comma-separated), numbers (e.g. 1,2), 'all', or 'none'.
   ```

4. **Load the selection** by invoking each chosen skill via the `Skill` tool. Track which were loaded so you can mention them in the wrap-up.

5. **Confirm and proceed.** One-line ack — "Loaded: nuxt, vue. Starting implementation." — so the user knows what's active driving the work.

### When to skip the question (but still record what was loaded)

- The user's original prompt explicitly named skills ("with the vue skill, do X") — load those, skip the prompt, move on.
- Ticket is clearly trivial (typo fix, one-line config tweak) — propose `none` as the default and ask once; if user agrees, proceed without loading anything.
- `skillSelection.askBeforeImplementation: false` is set in config — skip entirely (but the user gave up the safety net by setting that flag).

### Why this matters

The whole point of having many specialist skills is that they're focused — each one carries deep domain knowledge that doesn't pollute every conversation. Picking up front means:
- Implementation starts with the right context already in scope.
- The user sees and signs off on what's about to drive the work — fewer "wait, why is it suggesting that" moments mid-implementation.
- Off-domain skills don't waste tokens or risk wrong-domain advice.

## Step 6 — Commit

The full conventions live in `references/commit-conventions.md` — read it before crafting any commit. The short version:

If the project defines a `commitSkill.name`, invoke that skill via the `Skill` tool to perform the commit. Otherwise, craft the commit directly.

Follow `references/commit-conventions.md`. The high-level rules:

- **Atomic, dependency-ordered commits** — one concern per commit, foundations before consumers, refactors separated from features.
- **Conventional Commits format** by default: `<type>(<scope>): <subject>` + optional body + `Refs: <TICKET-ID>` trailer. Match the project's existing style if `git log` shows something different.
- **Imperative mood**, subject under 72 chars, body wrapped at 100.
- **Never mention AI/assistant authorship**. No `Co-Authored-By: Claude`, no "generated with" footer.

## Step 7 — Open a PR against the base branch

This is where the most common, costly mistake happens, so the procedure is precise.

The mechanism depends on `pullRequest.automation`:

- **`gh`** (default for GitHub-hosted repos): use the GitHub CLI commands below.
- **`manual`** (GitLab, Bitbucket, Gitea, internal tools, or no PR CLI installed): push the branch and render a copy-paste PR draft for the user. **Read `references/manual-pr.md`** and use the procedure there instead of the `gh` flow below. Most of the rest of this section (title format, body structure, base-branch discipline) still applies — the only change is the open-the-PR mechanism.

### Open the PR (gh mode)

```bash
gh pr create --base <baseBranch> \
  --title "<TICKET-ID>: <concise summary>" \
  --body "$(cat <<'EOF'
## Summary
- <bullet 1>
- <bullet 2>

## Test plan
- [ ] <how to verify>

Closes <TICKET-ID>
EOF
)"
```

### Why `--base` is mandatory

GitHub's repo-level default base branch is *not* always `main`. Teams accidentally set it to a long-running feature branch (`feature/MLG-50-core-database-schema` is a real example that bit this team) and forget. Without `--base`, `gh pr create` silently uses that default — your PR ends up targeting the wrong branch and dragging dozens of unrelated commits along. The only sign is a confused reviewer asking "why is this 47 commits?".

There is no exception. If the user wants a different base, they tell you so explicitly first.

### Verify after creation

```bash
gh pr view <number> --json baseRefName,commits \
  --jq '{base: .baseRefName, commitCount: (.commits | length)}'
```

The `base` must equal `git.baseBranch`. The `commitCount` must match the commits you just made on the feature branch. If either is off, retarget:

```bash
gh pr edit <number> --base <baseBranch>
```

Then re-verify. Don't move on until both checks pass.

### Reviewer logic (gh mode)

GitHub disallows requesting your own review. Apply this decision tree:

1. **`pullRequest.reviewers` is missing or empty** → omit `--reviewer` entirely. The user has explicitly opted out of automatic reviewer requests; review will be assigned manually if needed. Don't second-guess.
2. **`pullRequest.reviewers` has entries** → check actual repo collaborators:

   ```bash
   gh api repos/:owner/:repo/collaborators --jq '.[].login'
   ```

   - If the **only** collaborator is the same person who'd otherwise be the reviewer, omit `--reviewer` entirely. Review happens implicitly when they open the PR.
   - If there are other collaborators, request review from the configured reviewer(s) (mapped via `email -> githubHandle`).
   - If `pullRequest.skipSelfReview: true` and the PR author matches a configured reviewer, skip that reviewer (request from the others, if any).

In `manual` mode, reviewer info — if any — goes into the rendered PR draft body so the user can request reviews in their tool's UI. Empty/missing reviewers means the draft just omits the reviewer section.

### Title & body

- **Title:** `<TICKET-ID>: <concise summary>` — under 70 chars. (For `tracker.type: "none"`, just the summary.)
- **Body must include:**
  - `## Summary` section (1–3 bullets on the *why*)
  - `## Test plan` checklist
  - A ticket reference: `Closes <TICKET-ID>` for GitHub Issues; a Linear/Jira URL or smart-link for those trackers.

**If this branch was started via plan-kickoff (Step 0.5),** derive the `## Summary` and `## Test plan` from the captured plan — it already states the *why* and the intended verification, so you're not inventing them from the diff. Reconcile against what actually shipped: drop plan items you didn't end up doing, add anything material that emerged during implementation. Don't pad the checklist with test steps the plan never called for. If an issue was created from the same plan, its body and this PR Summary should tell one consistent story.

### Don't

- Merge the PR yourself. Approval is manual.
- Force-push after a review has been left without confirming with the user first. (Force-push before any review is fine.)

## Step 8 — Move the ticket to "In Review", attach the PR

Immediately after the PR opens (or, in manual PR mode, once the user has supplied the PR URL back), update ticket status to `tracker.statuses.inReview` and attach the PR URL. Tracker-specific calls in `references/<tracker>.md`.

- **Linear / Jira / GitHub Issues** → automatic via the tracker reference.
- **Manual tracker** → render a reminder for the user to update their offline tool and attach the PR URL there. See `references/manual-tracker.md`.
- **None** → skip.

For GitHub Issues, `Closes #N` in the PR body already auto-links — no separate attachment step needed, but you still update the status (label or Project field).

→ **Time tracking:** if `timeTracking.enabled`, log an entry for this round of work — estimate effort (use the anchors in `references/time-tracking.md`), confirm with the user, append to the ticket's time file. If the user is here because of follow-up changes after a previous review, this is just another entry on the same file; the total accumulates.

## Step 9 — Wait for merge confirmation, then close out

Don't preemptively mark the ticket Done. The PR may bounce back from review with changes; if you've already marked Done, the ticket lies about reality.

Wait for the user to confirm the merge (or check via `gh pr view <n> --json state` for `MERGED`). Then:

1. Update ticket to `tracker.statuses.done`.
2. Sync local base: `git checkout <baseBranch> && git pull --ff-only origin <baseBranch>`.
3. Delete the merged feature branch: `git branch -d <branch>`.
4. **Render the time-tracking output.** If `timeTracking.enabled`, mark the ticket's time file `completed`, then render the consolidated copy-paste block in the project's `timeTracking.outputFormat`. Format details in `references/time-tracking.md`.

The final output goes straight to the user, ready to paste into Linear/Jira/Toggl/wherever — that's the last thing they see when the ticket closes out.

## Pre-flight checklist

Run through this before starting each feature, and again before opening the PR. If any answer is "no", fix it before continuing.

0. Did the user explicitly opt into an ad-hoc fix (and does `adHocFixes.allowed` permit it)? If so — follow the **Escape hatch** section instead of this checklist: edit/commit/push on the current branch per `adHocFixes.scope`, no ticket, no PR ceremony — only never on `git.baseBranch`.
1. Am I on a feature branch (not the base branch)?
2. Did I resolve the ticket before branching — a valid id matching `tracker.ticketIdPattern`, an issue I just created, or an explicit no-ticket exception the user confirmed?
3. Is the ticket marked **In Progress**?
4. If `skillSelection.askBeforeImplementation`, did I ask the user which skills to load and load them?
5. Did I open the PR with explicit `--base <baseBranch>`? Did I verify base + commit count via `gh pr view`?
6. Did I move the ticket to **In Review** and attach the PR URL?
7. If `timeTracking.enabled`, did I log a time entry for this round (and confirm the estimate with the user)?
8. Has the user confirmed the merge before I marked the ticket **Done** and rendered the final time output?

## Reference files

Read these as needed during the workflow:

**Plan-kickoff** (consult at Step 0.5 when the user kicks off from a plan file or pasted plan text):
- `references/plan-kickoff.md`

**Setup wizard** (consult at Step 0 when no config exists, or whenever the user asks to set up / reconfigure the flow):
- `references/setup-wizard.md`

**Tracker-specific** (consult at Steps 2, 4, 8, 9 — pick by `tracker.type`; the "Create an issue" sections back Step 2's create-issue option):
- Linear → `references/linear.md`
- Jira → `references/jira.md`
- GitHub Issues → `references/github-issues.md`
- Manual (no automated tracker) → `references/manual-tracker.md`
- None → `references/no-tracker.md`

**Pull request mode** (consult at Step 7 — pick by `pullRequest.automation`):
- `gh` → instructions inline in Step 7
- `manual` → `references/manual-pr.md`

**Commit conventions** (consult at Step 6 when crafting commits directly):
- `references/commit-conventions.md`

**Time tracking** (consult at Steps 4, 8, and 9 when `timeTracking.enabled`):
- `references/time-tracking.md`

## When this skill should and shouldn't trigger

**Trigger when** the user:
- Starts work on a ticket ("let's work on MLG-123", "I need to do PROJ-42")
- Hands you an execution plan / spec / PRD / todo file — a path (`tasks/feat-x/todo.md`) or pasted plan text — and wants a branch created to start the work ("here's the plan, kick it off", "go ahead and write the plan… now start it")
- Asks to open a PR for a feature/fix
- Asks "what branch should I use?" or "should I branch off main?"
- Wants to update a ticket status because they finished something
- Mentions wanting to push, merge, or close out a piece of feature work
- Wants to set up or reconfigure the workflow for a project — no `.dev-flow/config.json` yet, or asks to change tracker / base branch / PR / commit / time-tracking settings (run the Step 0 setup wizard)

**Don't trigger for:**
- General git questions ("how do I rebase?")
- Exploratory work the user explicitly says is throwaway
- Reading code, writing code that isn't a discrete ticket-tracked piece of work
- Hotfix-on-main flows where the user has explicitly opted out of ticket tracking for that change

## Scope note

The skill works with any git host. PR creation has two modes:
- `pullRequest.automation: "gh"` — uses GitHub CLI; assumes GitHub-hosted repo.
- `pullRequest.automation: "manual"` — pushes the branch and renders a copy-paste PR draft. Works anywhere — GitLab, Bitbucket, Gitea, internal Bitbucket Server, etc.

A future version could add `pullRequest.automation: "glab"` (GitLab CLI) and similar; out of scope for v1.
