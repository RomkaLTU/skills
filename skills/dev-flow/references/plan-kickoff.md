# Plan-kickoff mode

Consulted from **SKILL.md Step 0.5** when the user hands you an execution plan instead of a ticket id. The job: turn the plan into a branch with work underway, resolving the ticket along the way. This is the bridge between a planning session (e.g. the output of a grilling or PRD skill) and the ticket-driven flow — so unlike the everyday "start work on `TICKET-ID`" path, plan-kickoff is expected to *create the branch* itself.

## 1. Detect what the user passed

Route by the content of the argument or the inline reference — no special flag:

- **Plan file** — a token that resolves to an existing file. Check before assuming: `test -f "<arg>"`. Common shapes: `tasks/<branch>/todo.md`, `docs/plan.md`, `*.md` paths. Read it.
- **Ticket id** — matches `tracker.ticketIdPattern`, or a bare integer when config has a single `ticketPrefix`. This is the *normal* flow; don't enter plan-kickoff.
- **Inline plan** — substantial free-form prose (multi-sentence, describes work to do) that is neither a path nor a ticket id. Capture it verbatim.
- **Nothing** — no plan and no id. Fall through to the normal flow and ask for a ticket (SKILL.md Step 2).

A file path that doesn't exist is a likely typo, not an inline plan — say so and ask, rather than treating the path string as plan prose. When a short string could be either an inline plan or a ticket reference, ask one quick question; guessing wrong sends the whole flow down the wrong branch.

## 2. Read the plan and extract the kickoff material

Whether file or inline text, pull out three things:

- **Summary** — one line, from the plan's title / first heading. Drives the PR title and (if created) the issue summary.
- **Type** — `feature` / `fix` / `chore` / `refactor`. Infer from the plan's framing ("add", "fix", "bump", "refactor") or a `tasks/<type>-…` path segment (`tasks/feat-newsletter-subscription/` → `feature`). Ask only if genuinely ambiguous.
- **Kebab description** — 3–6 lowercase words for the branch name, from the summary.

**Remember where the plan lives.** Note the file path (or, for inline text, that you're holding it in context). You'll reuse it twice: to populate a created issue's body (§4) and to write the PR Summary + Test plan at Step 7. Don't paraphrase-and-forget — the plan is the source of truth for the rest of the flow.

## 3. Resolve the ticket — the double-check before branching

Plan in hand, do **not** branch yet. First confirm the ticket, because the branch name, commit trailer, and PR title all depend on it. Ask explicitly (SKILL.md Step 2 has the full rules):

> Before I branch — what ticket does this belong to?
>   1. Paste a ticket id (e.g. `MLG-42`)
>   2. Create an issue now in `<tracker.type>` from this plan
>   3. Proceed without a ticket (no-ticket branch)

- **Id given** → validate against `tracker.ticketIdPattern`, fetch it if the tracker has read access (confirms it exists, may refine the summary), proceed.
- **Create an issue** → §4 below.
- **No ticket** → explicit exception. Branch drops the id segment (`feature/<kebab>`), commits omit `Refs:`, status steps are skipped. Confirm once; for team repos nudge toward option 2.

Honor `requireTicket`: when `true`, lead with options 1–2 and make 3 a deliberate override; when `false`, 3 is a fine default. The point of asking rather than defaulting is that silently branching ticket-less is exactly the drift this skill exists to prevent.

## 4. Creating an issue from the plan

When the user picks "create an issue", you already have everything — the plan *is* the issue content. Build it:

- **Title** ← the plan summary (concise, imperative).
- **Body** ← a trimmed version of the plan: the goal, scope, and acceptance criteria. For a file plan, summarize or link rather than pasting hundreds of lines; for a short inline plan, include it. Keep it useful to a human opening the issue cold.

Then call the tracker's create operation — see the **"Create an issue"** section in:
- `references/jira.md` (MCP `createJiraIssue` or REST `POST /rest/api/3/issue`)
- `references/github-issues.md` (`gh issue create`)
- `references/linear.md` ("Create an issue")

Scope creation to the configured `project`/`team`; never open into a different project without confirming. The returned id/number becomes the ticket for all naming. The new issue starts in its tracker's default status — you still move it to `tracker.statuses.inProgress` at Step 4.

**`tracker.type: "manual"`** → there's no remote API. "Create an issue" means generating a local id and storing the plan as the ticket description in `.dev-flow/tickets/<id>.json` per `references/manual-tracker.md`. **`tracker.type: "none"`** → there's nothing to create; this option isn't offered, go to the no-ticket branch.

If the plan describes several independent pieces of work that each deserve their own ticket (not one feature), that's the `to-issues` skill's job — mention it rather than cramming a multi-issue breakdown in here.

## 5. Branch, then continue the normal flow

With the ticket resolved:

1. **Branch** (SKILL.md Step 3) from `<baseBranch>`, named `<type>/<TICKET-ID>-<kebab>` (or `<type>/<kebab>` for no-ticket).
2. **In Progress** (Step 4) — move the ticket; skip silently if the tracker has no API access or `statusManagement: "skip"`.
3. **Skill selection** (Step 5) — the plan tells you which specialists fit; suggest them and ask, unless `skillSelection.askBeforeImplementation: false`.
4. **Implement following the plan** — work the plan's steps in order. If the plan has a checklist, track against it.
5. **Commit / PR / close out** (Steps 6–9) as usual. At PR time, derive `## Summary` and `## Test plan` from the plan (Step 7), reconciled against what actually shipped.

## Worked example

User: `/dev-flow tasks/feat-newsletter-subscription/todo.md`

1. `test -f` passes → read the file. Title "Newsletter subscription — endpoint + subscriber model"; path segment `feat-` → type `feature`; kebab `newsletter-subscription`.
2. Ask the ticket question. User has no id but says "make one".
3. Config is `tracker.type: "jira"`, project `MLG`. Capability check passes → create issue: title "Newsletter subscription — endpoint + subscriber model", body from the plan's Context + Scope + Acceptance criteria. Returns `MLG-357`.
4. Branch `feature/MLG-357-newsletter-subscription` off `main`; transition `MLG-357` → In Progress.
5. Suggest skills (e.g. `nestjs-best-practices`, `postgresql-table-design`), then implement the plan's sections. PR title `MLG-357: newsletter subscription endpoint + model`, Summary/Test plan from the plan.
