# Epic / subtask flow — branch from the epic branch, PR back to it

When the ticket being started is a **subtask of a parent ticket** (an epic), the work doesn't hang off
`git.baseBranch` — it hangs off the **epic's branch**:

```
main ──────────────────────────────────────────▶ (epic PR, opened by the user)
  └── epic/MLG-190-booking-overhaul ───────────▶
        ├── feature/MLG-120-reminder-model   → PR base: epic/MLG-190-booking-overhaul
        └── feature/MLG-121-reminder-ui      → PR base: epic/MLG-190-booking-overhaul
```

Subtask branches are created **from** the epic branch and their PRs target the epic branch. The epic
branch itself goes to `git.baseBranch` in a single PR **that the user opens** — the agent renders the
command but never runs it (see *Epic close-out* below).

Throughout this file, **work base** means the branch a subtask branches from and PRs back to: the epic
branch for subtasks, `git.baseBranch` for everything else.

## When this flow applies

All of the following must hold:

1. `epics.enabled` is not `false` in config (absent = enabled).
2. The ticket has a parent, established either by the tracker (the parent-detection section of
   `references/<tracker>.md`) or by the user saying so ("MLG-120 is part of the MLG-190 epic").
   For `tracker.type: "manual"` or `"none"` — and in any tracker's degraded/fallback mode — there is
   no API to ask, so the flow applies **only** when the user states the parent.

Detection is automatic but not silent: when the tracker reports a parent, tell the user in one line
before deviating from the normal flow — *"MLG-120 is a subtask of MLG-190 — branching from the epic
branch instead of main."* — and proceed. If the user objects, fall back to the normal flow from
`git.baseBranch` for this branch.

**Nesting:** the work base is always the **immediate** parent's branch. If the parent is itself a
subtask, the same rule applied recursively when *its* branch was created — you don't need to walk the
chain, just use the parent's branch.

## Resolve the epic branch

1. Fetch first so remote branches are visible:

   ```bash
   git fetch <git.remote> --prune
   ```

2. Search local and remote branches for the parent's ticket id:

   ```bash
   git branch --list "*<EPIC-ID>*" --all
   ```

3. Route by match count:
   - **Exactly one** → that's the work base. Check it out (or track it) and pull `--ff-only` so the
     subtask starts from the epic's current tip.
   - **Multiple** → ask the user which one is the epic branch; don't guess between, say, an old
     `feature/MLG-190-spike` and `epic/MLG-190-booking-overhaul`.
   - **None** → create it (next section).

## Create the epic branch when it doesn't exist

The first subtask bootstraps the epic. Build the branch off an up-to-date base:

```bash
git checkout <baseBranch> && git pull --ff-only <git.remote> <baseBranch>
git checkout -b <epics.branchPrefix>/<EPIC-ID>-<short-kebab-description> <baseBranch>
```

- `epics.branchPrefix` defaults to `epic`, giving `epic/MLG-190-booking-overhaul`.
- Derive `<short-kebab-description>` from the **parent ticket's title** — fetch it via the tracker
  reference, same as Step 2 does for the subtask. If the parent can't be fetched, ask the user for a
  one-liner; don't invent one.
- The epic branch must exist **on the remote** before the subtask's PR can target it. This push is a
  write step, so it follows the `handoff.push` gate: by default render the command for the user
  (`git push -u <git.remote> <epic-branch>`) alongside the subtask's own push at Step 7; only run it
  yourself when `handoff.push: false`. Nothing needs pushing at creation time — local is fine until
  the PR.

Then create the subtask branch from it, per Step 3's naming but with the epic branch as the start
point:

```bash
git checkout -b <type>/<TICKET-ID>-<description> <epic-branch>
```

## What changes in the main flow

Run Steps 1–9 as written, substituting the work base wherever the base branch appears:

| Step | Normal flow | Subtask flow |
|------|-------------|--------------|
| 1 — sync & branch from | `git.baseBranch` | the epic branch (pull `--ff-only` first) |
| 3 — `git checkout -b … <start>` | `<baseBranch>` | `<epic-branch>` |
| 7 — pre-push sanity check | `git log <baseBranch>..HEAD` | `git log <epic-branch>..HEAD` |
| 7 — `gh pr create --base` | `<baseBranch>` | `<epic-branch>` |
| 7 — verify `gh pr view` base | equals `git.baseBranch` | equals the epic branch |
| 9 — sync after merge | base branch | epic branch (`git checkout <epic-branch> && git pull --ff-only`) |

Everything else is unchanged:

- **Statuses move on the subtask ticket only.** In Progress / In Review / Done at Steps 4, 8, 9 apply
  to the subtask. **Don't transition the epic ticket** — most trackers roll epic progress up from
  sub-issues, and an agent flipping the epic's status fights that. The one exception is the epic
  close-out below, after the user confirms the epic → base merge.
- **Handoff gates** (commit / push / PR) work exactly as in Steps 6–7.
- **Time tracking** logs against the subtask ticket.

One guardrail gains weight here: the wrong-base failure mode now has two wrong answers (base branch
instead of epic branch, or a sibling subtask's branch), so the Step 7 `--base` + `gh pr view`
verification is **not skippable** in this flow.

If the epic branch has drifted far behind `git.baseBranch`, surface it ("the epic branch is 30 commits
behind main — consider updating it before this subtask") but leave the update to the user: merging or
rebasing base into a shared epic branch is exactly the kind of long-lived-branch promotion this skill
doesn't do on its own.

## Epic close-out — the epic → base PR is the user's

When the user says the epic is complete (or asks to close it out), prepare — don't perform:

1. **Check the children.** Via the tracker (sub-issues all Done?) and via git
   (`git log <baseBranch>..<epic-branch> --oneline` shows the merged subtask work). Surface anything
   still open and let the user decide whether to proceed.
2. **Sync the epic branch** locally (`git checkout <epic-branch> && git pull --ff-only`).
3. **Render the PR command** — regardless of `handoff.pullRequest`, this one is always handed off;
   promoting the epic into the base branch is the user's call, consistent with the skill's scope note:

   > Epic looks complete. To open the epic PR, run:
   > ```bash
   > gh pr create --base <baseBranch> --head <epic-branch> \
   >   --title "<EPIC-ID>: <epic summary>" \
   >   --body "…summary of the subtasks that landed, with their ticket ids…"
   > ```
   > Paste the PR URL once it's open and I'll verify the base.

   In `pullRequest.automation: "manual"` mode, render the draft per `references/manual-pr.md` instead.
4. **After the user confirms the epic PR merged**, run the normal Step 9 close-out for the **epic
   ticket**: move it to Done, sync `git.baseBranch`, delete the epic branch (and any leftover subtask
   branches already merged into it).
