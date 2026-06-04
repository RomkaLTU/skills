# Manual PR mode

When `pullRequest.automation: "manual"`, the assistant doesn't run `gh pr create`. Instead it pushes the branch and renders a copy-paste PR draft — title, base, body, reviewers — for the user to paste into whatever PR tool they actually use (GitLab MR form, Bitbucket PR form, Gitea, an internal Bitbucket Server, etc.).

## Why no automation

The host might be GitLab, Bitbucket, Gitea, Bitbucket Server, an internal fork of any of these, or something custom. Each has its own CLI (`glab`, no first-party Bitbucket CLI, etc.), its own auth, its own quirks. v1 deliberately doesn't try to abstract over them — render the draft, let the human take 20 seconds to paste it. That's far more reliable than guessing wrong about the tool.

If a project regularly uses GitLab and wants automation later, a future `pullRequest.automation: "glab"` mode + `references/glab.md` is a small lift. Out of scope for now.

## Step 7 procedure (replaces the `gh pr create` flow)

### 1. Push the branch

```bash
git push -u <git.remote> HEAD
```

`git.remote` defaults to `origin`. **Respect the `handoff.push` gate:** by default (true or absent) you render that command and ask the user to run it, then wait — don't push yourself. Only `handoff.push: false` lets you run the push.

Once it's pushed, capture the push output — most hosts (GitLab, GitHub, Gitea) print a "Create a merge request" / "Create a pull request" URL when pushing a new branch. Surface it to the user verbatim:

> "Branch pushed. Your host suggested this URL to open the PR:
> `<url-from-push-output>`
>
> Use it, or paste the draft below into your PR form."

### 2. Render the draft

Output exactly this block (substitute values from config and the work-in-progress):

```
=== Pull Request Draft ===
Source:  <branch>
Target:  <baseBranch>
Title:   <TICKET-ID>: <concise summary>

Reviewers (request manually in your PR tool):
- <reviewer email or handle>

--- Body ---
## Summary
- <bullet 1>
- <bullet 2>

## Test plan
- [ ] <how to verify>

Refs: <TICKET-ID>
<ticket URL if known>
=========================
```

Adjustments by tracker type:
- `tracker.type: "github-issues"` → swap `Refs: <TICKET-ID>` for `Closes #<n>`. (Only auto-links inside actual GitHub PRs; in GitLab/Bitbucket bodies it's just human-readable text.)
- `tracker.type: "manual"` → include the local ticket file's `url` field if set, on its own line under `Refs:`.
- `tracker.type: "none"` → drop the `Refs:` line entirely.

### 3. Wait for the PR URL back from the user

After rendering, ask:

> "Paste the PR/MR URL once you've opened it — I'll continue from Step 8."

Don't try to guess the URL. Wait for the user to confirm it's open and supply the URL. Then proceed to Step 8 (move ticket to In Review, attach PR URL).

## Verification

The base-branch verification step from Step 7 still applies in spirit, even though `gh pr view` isn't available:
- Before pushing, sanity-check `git log --oneline <baseBranch>..HEAD` — does the commit list match what you intended? Anything weird (commits from elsewhere, wrong base divergence point) shows up here.
- After the user reports the PR is open, ask once: "Does the PR show only the commits we just made, targeting `<baseBranch>`?" — gives the user a chance to catch a stale-base mistake before review starts.

## What still applies

Everything in Step 7 about commit message conventions, PR title length, body structure (`## Summary` + `## Test plan`), and "don't merge yourself / don't force-push after review" — all unchanged. The only change is the *mechanism* for opening the PR.
