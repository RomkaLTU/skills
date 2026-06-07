# Setup wizard

Run this wizard from Step 0 of the skill when `.dev-flow/config.json` doesn't exist yet, or whenever the user asks to set up or reconfigure the dev-flow workflow for a project. Goal: produce a working `.dev-flow/config.json`, asking the user only what can't be detected.

## Step 0 — Check for existing config

If `.dev-flow/config.json` already exists:
1. Read it.
2. Show the user the current values.
3. Ask: "Reconfigure everything, change a specific section, or exit?"
4. If "specific section", ask which (tracker / pull request / commits / time tracking) and walk only that part.

If no config exists, proceed to auto-detect.

## Step 1 — Auto-detect

Run these probes silently and stash the results:

```bash
# Git host (look at remote URL)
git remote get-url origin 2>/dev/null

# Default base branch (per remote HEAD)
git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@'

# Git remote name (usually origin)
git remote 2>/dev/null | head -1

# gh CLI installed and authenticated?
which gh >/dev/null && gh auth status 2>&1 | grep -q "Logged in" && echo "gh-ok" || echo "gh-missing"

# Existing commit skill? The reliable, vendor-neutral signal is THIS session's
# available-skills list — if a "commit" skill shows up there, it's usable no
# matter which agent/tool is running. As a filesystem fallback, glob the common
# per-tool skill locations (this detects another tool's skill wherever it lives;
# it is not where dev-flow stores its own config):
for d in .agents/skills .claude/skills .cursor/skills .opencode/skills; do
  f="$d/commit/SKILL.md"
  [ -f "$f" ] && { echo "commit-skill-yes ($f)"; \
    grep -q "disable-model-invocation: true" "$f" 2>/dev/null && echo "gated"; }
done

# Repo basename (slug fallback)
basename "$(git rev-parse --show-toplevel 2>/dev/null)"
```

Also check the current Claude session's loaded MCP tools:
- If `mcp__claude_ai_Linear__*` tools are available → Linear MCP present
- If Atlassian/Jira tools are available → Jira MCP present

Surface what you found before asking, e.g.:

> "Auto-detected:
> - Git host: github.com
> - Base branch: main
> - `gh` CLI: installed and authenticated
> - Project commit skill: yes (gated with `disable-model-invocation: true`)
> - Linear MCP: available
>
> I'll use these as defaults — let me know if anything's off."

## Step 2 — Tracker

Ask:

> "What project-management tool tracks tickets for this project?
> 1. **linear** — Linear MCP `<detected: yes/no>`
> 2. **jira** — Jira MCP/API `<detected: yes/no>`
> 3. **github-issues** — `gh` CLI `<detected: yes/no>`
> 4. **manual** — you'll type ticket id + title each time (the skill stores them locally)
> 5. **none** — no ticket tracking, branch/PR discipline only"

### Follow-up questions per tracker type

**linear / jira / github-issues:**
- "Team key?" (e.g. `MLG`, `BACK`)
- "Project key?" (often same as team)
- "Ticket prefix?" (default: same as team key; for GitHub Issues, often empty or `issue`)
- "Ticket id pattern?" (default: derived from prefix → `^<PREFIX>-\\d+$`)
- "Status names — defaults are `In Progress`, `In Review`, `Done`. Different in your workspace?"

**manual:**
- "Ticket prefix?" (e.g. `TASK`, `STORY`, or empty)
- Read `references/manual-tracker.md` for the rest of the workflow contract.

**none:**
- No further tracker questions.

## Step 3 — Base branch

Show detected default; ask "Use `<detected>`?" (default yes).

## Step 4 — Pull request automation

Ask:

> "How are PRs created?
> 1. **gh** — use the GitHub CLI `<detected: yes/no, host: github.com|other>`
> 2. **manual** — output a copy-paste PR draft I'll paste into [GitLab MR / Bitbucket PR / internal tool]"

Default proposal:
- Host = github.com AND `gh` is installed → propose `gh`
- Otherwise → propose `manual`

If `gh`:
- Ask reviewer email + GitHub handle, *unless* the user is the only collaborator (`gh api repos/:owner/:repo/collaborators --jq '. | length'` → 1).
- Confirm `skipSelfReview: true` (default).

If `manual`:
- Ask which host so PR draft wording can be appropriate ("Merge Request" for GitLab, etc.). Optional — default to neutral language.
- Skip reviewer questions (those go inline in the draft body for the user to handle).
- Read `references/manual-pr.md` for the workflow contract.

## Step 5 — Commit skill & write-step handoff

First, the commit skill. If a project commit skill was detected:

> "I see this project has its own `commit` skill `<gated: yes/no>`. I'll point you at it when it's time to commit."

Record `commitSkill.name` if one exists (it's used in the handoff message). If none is detected, omit the `commitSkill` block — the assistant drafts commit messages per `references/commit-conventions.md`.

Then, the handoff. Ask:

> "When implementation is done, who runs the write steps?
> 1. **handoff (default)** — I prepare the commit message, push command, and PR draft, then hand each step back to you to run manually (commit → push → PR). Nothing is committed, pushed, or PR'd without you.
> 2. **automatic** — I commit, push, and open the PR myself."

Default proposal: `handoff` (all three true). This is the safe default — explicit human authorization before every git write.

- Choosing **handoff** → omit the `handoff` block (it defaults on) *or* write it explicitly for clarity. Optionally let the user pick per-step (e.g. auto-commit but hand off the PR) and write only the keys they flip.
- Choosing **automatic** → write `"handoff": { "commit": false, "push": false, "pullRequest": false }`.

## Step 6 — Skill selection mode

Ask:

> "Before each implementation, how should I handle loading specialist skills (vue, nuxt, laravel-simplifier, claude-api, etc.)? **ask** = pause and let you pick (default); **auto** = pick the relevant ones from the ticket and load them without asking; **skip** = don't load any."

Default: `skillSelection.mode: "ask"` (equivalently the legacy `skillSelection.askBeforeImplementation: true`). Note that **headless / unattended runs always behave as `auto` regardless of this setting**, so an automated loop never blocks on the skill picker — it selects skills from the ticket context and proceeds.

## Step 7 — Time tracking

Ask:

> "Track time as a senior dev would log it, with copy-paste output for time-tracking tools? (default: yes)"

If yes:
- Output format — ask only if user wants something other than `default`:
  - `default` (human-readable block)
  - `jira-worklog`
  - `toggl-csv`
  - `plain`
- Storage — default `repo` (gitignored). Offer `user` (in `~/.dev-flow/`) or `none` only if asked.

## Step 8 — Confirm and write

Render the assembled JSON back to the user. Ask:

> "Write this to `.dev-flow/config.json`?"

On yes:

```bash
mkdir -p .dev-flow
# Write the JSON file (use the assistant's file-write tool; cat <<EOF works in a pinch)
```

Don't eagerly add anything to `.gitignore` here — that happens lazily on first time-entry write (per `references/time-tracking.md`). But if `tracker.type: "manual"` AND the user says they want to start adding tickets immediately, also add `.dev-flow/tickets/` to `.gitignore` per `references/manual-tracker.md`.

Confirm:

> "Done. The skill will pick this up next time it triggers — try saying 'let's start work on `<TICKET-ID>`'."

## Output examples

**Project on Linear + GitHub + gated commit skill (e.g. MLG):**

```json
{
  "tracker": {
    "type": "linear",
    "team": "MLG",
    "project": "MLG",
    "ticketPrefix": "MLG",
    "ticketIdPattern": "^MLG-\\d+$",
    "statuses": { "inProgress": "In Progress", "inReview": "In Review", "done": "Done" }
  },
  "git": { "baseBranch": "main", "remote": "origin" },
  "pullRequest": {
    "automation": "gh",
    "reviewers": [{ "email": "hello@codesomelabs.com", "githubHandle": "RomkaLTU" }],
    "skipSelfReview": true
  },
  "commitSkill": { "name": "commit" },
  "handoff": { "commit": true, "push": true, "pullRequest": true },
  "requireTicket": true,
  "skillSelection": { "askBeforeImplementation": true },
  "timeTracking": { "enabled": true, "outputFormat": "default", "storage": "repo" }
}
```

(The `handoff` block above is the default and could be omitted — it's spelled out here so it's discoverable. Drop in `"handoff": { "commit": false, "push": false, "pullRequest": false }` for the fully-automatic flow.)

**Project with no Linear, no `gh` (e.g. self-hosted Gitea + offline tracker):**

```json
{
  "tracker": { "type": "manual", "ticketPrefix": "TASK" },
  "git": { "baseBranch": "main", "remote": "origin" },
  "pullRequest": { "automation": "manual" },
  "requireTicket": true,
  "skillSelection": { "askBeforeImplementation": true },
  "timeTracking": { "enabled": true, "outputFormat": "default", "storage": "repo" }
}
```

**Personal project, no ticketing, no PRs (just push to main with discipline):**

```json
{
  "tracker": { "type": "none" },
  "git": { "baseBranch": "main", "remote": "origin" },
  "pullRequest": { "automation": "manual" },
  "requireTicket": false,
  "skillSelection": { "askBeforeImplementation": false },
  "timeTracking": { "enabled": false }
}
```

## Reconfiguration mode

When `.dev-flow/config.json` exists, show current values and offer per-section edits. Walk the matching question(s) only — don't re-ask the entire wizard. After edits, re-render and confirm before overwriting.
