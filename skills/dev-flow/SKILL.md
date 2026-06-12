---
name: dev-flow
version: 1.4.0
description: >-
  Run a ticket-driven git workflow: choose the base branch, tie work to a project-management ticket, name branches and commits, open PRs against the right base, verify before review, and move ticket statuses. Use when starting work from a ticket id or bare number, kicking off a plan/spec/PRD/todo file, asking what branch to use, opening a PR, syncing tracker status after branch or merge work, or setting up/reconfiguring `.dev-flow/config.json` for tracker, base branch, PR, commit, or time-tracking settings. Do not use for code review of an existing PR, one-off commits on an already-created branch, breaking a plan into many issues, writing PRDs, configuring CI, release/integration branch promotion, or generic git how-to questions.
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
  "epics": {
    "enabled": true,                        // default: true — when the ticket has a parent (epic), branch
                                            // the subtask from the epic's branch and PR back to it
                                            // (see Step 2.5). false = always branch from git.baseBranch.
    "branchPrefix": "epic"                  // prefix when bootstrapping an epic branch: epic/<EPIC-ID>-<desc>
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
  "delegation": {                           // optional: route low-judgment LLM steps to a faster/cheaper model
    "commitMessage": {                      // currently the only delegable step — see references/delegation.md
      "enabled": true,
      "models": {                           // key = host-agent family, value = that agent's model id;
        "claude": "haiku",                  // open-ended — add "opencode", "gemini", etc. as needed
        "codex": "gpt-5.1-codex-mini",
        "cursor": "composer-1"
      }
    }
  },
  "handoff": {                              // who runs the write steps once implementation is done.
                                            // Each defaults to true: the agent PREPARES the step
                                            // (message, push command, PR draft, base checks) but the
                                            // USER runs it. Set a key to false to let the agent do it.
    "commit":      true,                    // true (default) = user commits (e.g. via the commit skill)
    "push":        true,                    // true (default) = user pushes the branch
    "pullRequest": true                     // true (default) = user opens the PR; false = agent runs `gh pr create`
  },
  "requireTicket": true,                    // false = allow no-ticket branches by default
  "skillSelection": {
    "askBeforeImplementation": true,        // legacy boolean: true → ask, false → skip. Superseded by `mode`.
    "mode": "ask"                           // "ask" (default) = prompt the user which skills to load;
                                            // "auto" = select skills from the ticket context and load them
                                            //          without asking; "skip" = load nothing.
                                            // Headless / unattended runs force "auto" regardless (see Step 5).
  },
  "timeTracking": {
    "enabled": true,                        // false to skip every time-tracking step
    "outputFormat": "default",              // "default" | "jira-worklog" | "toggl-csv" | "plain"
    "storage": "repo"                       // "repo" (default, gitignored) | "user" | "none"
  }
}
```

Once loaded, hold these values in your head for the rest of the session — they drive every decision below.

**Handoff is the default.** If the `handoff` block is absent, treat all three keys as `true`: the agent never commits, pushes, or opens a PR on its own. It does all the preparation — crafts the commit, runs the base-branch checks, drafts the PR title/body, renders the exact commands — then **stops and hands each write step back to the user to run manually**, in order: commit → push → PR. Only a key explicitly set to `false` lets the agent perform that step itself (the old fully-automatic behavior). This is enforced in Steps 6–7 below.

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
>
> **One exception:** when the ticket is a **subtask of an epic** (Step 2.5), the epic's branch replaces the base branch as the *work base* — the subtask branches from it and PRs back to it. The epic branch itself still goes to `git.baseBranch` via a PR the user opens (the agent renders the command at close-out — see `references/epic-subtasks.md`).

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

Once you have a valid id, fetch the ticket via the tracker reference for your `tracker.type` (see [Reference files](#reference-files)) so you can confirm it exists and read the description. The description usually gives you the right wording for the branch name and PR title. **While you're looking at the fetched ticket, also read its parent field** — that's the input to Step 2.5.

## Step 2.5 — Subtask of an epic? Branch from the epic branch

Some tickets aren't standalone — they're sub-issues of a parent ticket (an epic). Those don't branch from `git.baseBranch`: the subtask branches **from the epic's branch** and its PR targets the epic branch, so the epic accumulates its subtasks and lands on the base branch as one reviewable unit.

When fetching the ticket at Step 2, check whether it has a parent — each tracker reference has a **"Detect a parent"** section with the exact call. If `epics.enabled` isn't `false` and a parent exists (or the user says the ticket belongs to an epic), **read `references/epic-subtasks.md` and follow it**. In short:

1. Tell the user in one line that you're switching to the epic flow (detection is automatic, not silent).
2. Resolve the epic's branch — search local + remote for the parent's ticket id; if no branch exists yet, bootstrap `<epics.branchPrefix>/<EPIC-ID>-<desc>` from an up-to-date base.
3. Run the rest of the flow with the epic branch as the **work base**: branch from it (Steps 1/3), sanity-check and PR against it (Step 7), sync it after merge (Step 9). Statuses still move on the *subtask* ticket only — never auto-transition the epic.
4. The epic → base PR is **always** the user's to open, regardless of `handoff` — at close-out the agent verifies the children and renders the command.

For `tracker.type: "manual"` / `"none"`, or any tracker in degraded mode, there's no parent field to read — the flow applies only when the user states the parent. No parent, or `epics.enabled: false` → continue with the normal flow; nothing changes.

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

For an epic subtask (Step 2.5), the start point is the epic branch, not `<baseBranch>`.

When `tracker.type: "none"`, drop the ticket id segment: `fix/login-redirect-loop`.

## Step 4 — Move the ticket to "In Progress"

As soon as the branch exists and you're starting implementation, move the ticket to `tracker.statuses.inProgress`. The tracker-specific calls live in `references/<tracker>.md`.

**Skip this step silently** when any of the following holds — branch and PR work still proceed normally:
- `tracker.statusManagement` is `"skip"`.
- The tracker-specific capability check (in `references/<tracker>.md`) reports no API access (e.g. Jira configured but no MCP issue-management tools and no `JIRA_*` env credentials).

The same skip applies to Step 8 (move to In Review) and Step 9 (move to Done).

**Don't self-assign.** If the ticket is unassigned, leave assignment to the user — they may be doing the work, or they may have delegated it to you while keeping the ticket on themselves.

→ **Time tracking:** if `timeTracking.enabled`, create or open the ticket's time file and set/update the `started` timestamp. See `references/time-tracking.md`.

## Step 5 — Load the skills this task needs

Before any implementation begins, bring the right specialist skills into scope. Different tickets benefit from different specialists — `pest-testing` for tests, `inertia-react-development` / `tailwindcss-development` for UI, `medialibrary-development` for uploads, `pennant-development` for feature flags, `claude-api` for Anthropic SDK code, `simplify` for general cleanup, etc. Skills brought into context cost tokens, so the aim is a tight, relevant set — not the whole inventory.

This step resolves to one of three modes, and **the mode is chosen automatically** so the skill behaves correctly whether a human is driving or it's running headless inside an automated loop:

- **`ask`** — suggest a set and let the user pick (the interactive default).
- **`auto`** — select the relevant skills from the ticket context and load them *without asking*.
- **`skip`** — load nothing.

### Decide the mode

Pick the first that applies:

1. **The prompt already decided.** If the invoking prompt named the skills to load ("with the vue skill, do X"), load exactly those and skip the rest of this step. If the prompt says to auto-select / not to pause / that the run is unattended ("auto-select the relevant skills", "don't ask which skills to load", "[unattended run]"), use **`auto`**.
2. **Config says so.** Read `skillSelection.mode` from the Step 0 config: `"ask"`, `"auto"`, or `"skip"`. If `mode` is absent, fall back to the legacy boolean `skillSelection.askBeforeImplementation` (`true` → `ask`, `false` → `skip`). Default when neither is set: `ask`.
3. **No human can answer.** If you're running non-interactively — a headless / print / batch session, `AskUserQuestion` is unavailable, or anything in context signals an unattended run ("no human is watching", "never call AskUserQuestion", a CI/loop preamble) — use **`auto`** regardless of config. **Unattended downgrades `ask` to `auto`, never to `skip`**: you still load the right skills, you just choose them yourself instead of asking.

> Why `ask → auto` (not `ask → skip`) when unattended: skipping was the old way an automated run avoided the prompt, and it threw away the whole benefit — implementation then ran with *no* domain skills in scope. Auto keeps the value (context-appropriate skills) without the blocking question.

### Build the candidate set (all modes)

Whether you ask or auto-load, compute the candidates the same way:

1. **Enumerate available skills** from the session's `<system-reminder>` messages (names + descriptions). Don't guess from training data — only skills actually present can be loaded.
2. **Match against the work** — the ticket title/description (fetched at Step 2), the plan if this was a plan-kickoff, and the parts of the codebase the change will touch. Produce 1–3 strong matches, each with a one-phrase reason. Always include the project's test skill (e.g. `pest-testing`) when the work will add or change tests — which is almost always.

### `ask` mode — interactive

1. Present the suggestion and the full list, and **ask the user** with `AskUserQuestion` (multi-select) if available; otherwise a numbered list with a comma-separated reply.

   ```
   Which skills should I load for MLG-123 (Add booking reminders)?

   Suggested: nuxt, vue
     - nuxt → reminder dispatch likely lives in server/api routes
     - vue  → user-facing reminder settings need an SFC

   All available: 1. vue  2. nuxt  3. laravel-simplifier  4. simplify  5. claude-api  …
   Reply with names, numbers (1,2), 'all', or 'none'.
   ```

2. **Load the selection** via the `Skill` tool, then confirm in one line — "Loaded: nuxt, vue. Starting implementation." — and proceed.

### `auto` mode — unattended / headless

1. **Do not call `AskUserQuestion`.** Take the candidate set you just computed as the selection (the 1–3 strongest plus the test skill).
2. **Load it** via the `Skill` tool.
3. **Note it in one line** so the transcript records the assumption — "Auto-loaded (unattended): pest-testing, inertia-react-development — UI slice with new tests." — then go straight to implementation.

This is the path that makes the skill safe inside automated loops (e.g. a Ralph-style runner): it never blocks on a question, and it still pulls in the domain skills the slice needs based on the *actual ticket*, not a fixed list.

### `skip` mode — load nothing

Only when `mode: "skip"` (or the legacy `askBeforeImplementation: false`) is set, or the ticket is genuinely trivial (typo / one-line config). Load nothing and proceed — the user or config has explicitly traded the safety net for speed.

### Why this matters

The whole point of having many specialist skills is that they're focused — each carries deep domain knowledge that shouldn't pollute every conversation. Resolving the set up front means implementation starts with the right context already in scope, off-domain skills don't waste tokens — and, crucially, an unattended run gets the same benefit a human would, without anyone there to pick.

## Step 6 — Commit

The full conventions live in `references/commit-conventions.md` — read it before planning any commit.

**Cheaper-model delegation:** if the Step 0 config has a `delegation.commitMessage` block with a model entry for the host agent you're running in, the *drafting* of the commit message(s) is delegated to that model — read `references/delegation.md` and follow it. Only the message text is outsourced; commit planning (grouping, ordering), staging, and every handoff gate below stay with you. No block or no matching entry → draft inline as usual, silently.

**Default (`handoff.commit` true or absent): the user commits, not you.** When implementation is done, don't run `git commit` or invoke the commit skill yourself. Instead:

1. Stage nothing automatically and run no commit. Work out the atomic, dependency-ordered commit plan and the message(s) per the conventions below, so the user isn't starting from scratch.
2. **Hand off to the user.** Tell them implementation is ready and ask them to commit manually. If the project defines `commitSkill.name`, point at it explicitly:

   > Implementation is ready. To commit, run your commit skill:
   > `/<commitSkill.name> <TICKET-ID>`
   >
   > Suggested commit(s):
   > - `<type>(<scope>): <subject>`  (Refs: <TICKET-ID>)
   >
   > I won't commit, push, or open the PR automatically — tell me when you're ready for the next step.

   With no `commitSkill.name`, drop the slash-command line and just present the suggested commit(s) for the user to apply.
3. **Wait.** Don't proceed to Step 7 until the user confirms the commit is done (or tells you to go ahead).

**Only when `handoff.commit: false`** does the agent perform the commit itself — invoke `commitSkill.name` via the `Skill` tool if defined, otherwise craft the commit directly.

Either way, the commit content follows `references/commit-conventions.md`. The high-level rules:

- **Atomic, dependency-ordered commits** — one concern per commit, foundations before consumers, refactors separated from features.
- **Conventional Commits format** by default: `<type>(<scope>): <subject>` + optional body + `Refs: <TICKET-ID>` trailer. Match the project's existing style if `git log` shows something different.
- **Imperative mood**, subject under 72 chars, body wrapped at 100.
- **Never mention AI/assistant authorship**. No `Co-Authored-By: Claude`, no "generated with" footer.

> The escape hatch (ad-hoc fixes) is separate: there the user has *explicitly* asked you to commit/push on the current branch, so `handoff` doesn't gate it — follow the **Escape hatch** section instead.

## Step 7 — Push, then open a PR against the base branch

This is where the most common, costly mistake happens, so the procedure is precise. Two write actions live here — pushing the branch and opening the PR — and each has its own handoff gate.

> **Epic subtask?** Everywhere this step says `<baseBranch>`, substitute the **work base** from Step 2.5 — the epic branch. The pre-push `git log` check, the `--base` flag, and the post-create verification all compare against the epic branch, and the verification is even less skippable here (two wrong answers exist: the base branch, or a sibling subtask's branch). Make sure the epic branch itself is on the remote first — if it was just bootstrapped, its push rides the same `handoff.push` gate.

### Push the branch (handoff gate)

**Default (`handoff.push` true or absent): the user pushes.** Once the commit exists, render the push command and ask the user to run it themselves:

> Ready to push. Run:
> `git push -u <git.remote> HEAD`
> (`git.remote` defaults to `origin`.) Tell me once it's pushed.

Wait for confirmation before touching the PR. **Only when `handoff.push: false`** does the agent run the push itself.

Either way, before pushing, sanity-check the commit list: `git log --oneline <baseBranch>..HEAD` should show only the commits you intended — nothing dragged in from a stale base.

### Open the PR (handoff gate)

The mechanism depends on `pullRequest.automation`:

- **`gh`** (default for GitHub-hosted repos): use the GitHub CLI command below.
- **`manual`** (GitLab, Bitbucket, Gitea, internal tools, or no PR CLI installed): render a copy-paste PR draft for the user. **Read `references/manual-pr.md`** and use the procedure there instead of the `gh` flow below. Most of the rest of this section (title format, body structure, base-branch discipline) still applies — the only change is the open-the-PR mechanism. (Manual mode is already a handoff — the user always opens the PR there.)

**Default (`handoff.pullRequest` true or absent): the user opens the PR.** In `gh` mode, *render* the exact command for the user to run rather than running it — then ask them to paste back the PR number or URL so you can verify it (see **Verify after creation**):

> Ready to open the PR. Run:
> ```bash
> gh pr create --base <baseBranch> \
>   --title "<TICKET-ID>: <concise summary>" \
>   --body "$(cat <<'EOF'
> ## Summary
> - <bullet 1>
> - <bullet 2>
>
> ## Test plan
> - [ ] <how to verify>
>
> Closes <TICKET-ID>
> EOF
> )"
> ```
> Paste the PR URL once it's open and I'll verify the base and commit count.

**Only when `handoff.pullRequest: false`** does the agent run `gh pr create` itself:

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

Verification is read-only, so run it regardless of the handoff setting — in handoff mode, once the user reports the PR number/URL back to you:

```bash
gh pr view <number> --json baseRefName,commits \
  --jq '{base: .baseRefName, commitCount: (.commits | length)}'
```

The `base` must equal `git.baseBranch`. The `commitCount` must match the commits you just made on the feature branch. If either is off, retarget:

```bash
gh pr edit <number> --base <baseBranch>
```

In handoff mode, flag the mismatch to the user and offer that `gh pr edit` retarget rather than silently editing their PR. Then re-verify. Don't move on until both checks pass.

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

Immediately after the PR opens — or, in handoff or manual PR mode, once the user has supplied the PR URL back — update ticket status to `tracker.statuses.inReview` and attach the PR URL. Tracker-specific calls in `references/<tracker>.md`.

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

**Epic subtask:** step 2 above syncs the *epic branch* instead of the base (the subtask merged into the epic, not into base), and the epic ticket stays untouched. When the *epic itself* is done, run the close-out in `references/epic-subtasks.md` — verify the children, then render (never run) the epic → `<baseBranch>` PR command for the user.

## Pre-flight checklist

Run through this before starting each feature, and again before opening the PR. If any answer is "no", fix it before continuing.

0. Did the user explicitly opt into an ad-hoc fix (and does `adHocFixes.allowed` permit it)? If so — follow the **Escape hatch** section instead of this checklist: edit/commit/push on the current branch per `adHocFixes.scope`, no ticket, no PR ceremony — only never on `git.baseBranch`.
1. Am I on a feature branch (not the base branch)?
2. Did I resolve the ticket before branching — a valid id matching `tracker.ticketIdPattern`, an issue I just created, or an explicit no-ticket exception the user confirmed?
2.5. Did I check the ticket's parent field (Step 2.5)? If it's a subtask of an epic, am I branched from — and PR'ing back to — the epic branch, not `git.baseBranch`?
3. Is the ticket marked **In Progress**?
4. Did I resolve skill loading per Step 5 — `ask` (prompted the user), `auto` (selected by ticket context and loaded without asking, the path headless/unattended runs always take), or `skip` — and load the chosen skills?
5. Unless a `handoff` key is explicitly `false`, did I hand the write steps back to the user — preparing the commit, the push command, and the PR rather than running them, and pausing at each gate?
6. When the PR was opened (by the user, or by me only if `handoff.pullRequest: false`), was it created with explicit `--base <baseBranch>`? Did I verify base + commit count via `gh pr view`?
7. Did I move the ticket to **In Review** and attach the PR URL?
8. If `timeTracking.enabled`, did I log a time entry for this round (and confirm the estimate with the user)?
9. Has the user confirmed the merge before I marked the ticket **Done** and rendered the final time output?

## Reference files

Read these as needed during the workflow:

**Plan-kickoff** (consult at Step 0.5 when the user kicks off from a plan file or pasted plan text):
- `references/plan-kickoff.md`

**Setup wizard** (consult at Step 0 when no config exists, or whenever the user asks to set up / reconfigure the flow):
- `references/setup-wizard.md`

**Epic / subtask flow** (consult at Step 2.5 when the ticket has a parent, and at Step 9 for the epic close-out):
- `references/epic-subtasks.md`

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

**Cheaper-model delegation** (consult at Step 6 when config has a `delegation.commitMessage` block):
- `references/delegation.md`

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
