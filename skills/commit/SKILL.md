---
name: commit
version: 1.0.1
disable-model-invocation: true
description: >-
  Turn the working tree into atomic commits written in Trau's commit convention:
  Conventional Commits subject, imperative and lowercase, under 72 characters, an
  optional `Refs: <TICKET>` trailer, no AI attribution, staged file by file. The
  ticket is optional — with none in play the commit says nothing about tickets at
  all. Run it explicitly with `/commit` (optionally `/commit COD-123`) when
  implementation is finished and you want it committed, or when dev-flow hands off
  with "please run your commit skill". Not for pushing, opening PRs, tagging
  releases, moving tracker statuses, or reviewing code.
---

# Commit — Trau's commit convention

## Why this exists

In a Trau-shaped repo the git log is not decoration. Release notes are generated
from the subjects, the commit and PR body together act as the design changelog,
and the person reading `git log` in two years is the only one still around who
cares why a line exists. That gives every message three jobs: say what changed in
a form a release note can quote, carry the ticket link that holds the reasoning,
and carry nothing else.

"Nothing else" is the part that erodes. Harnesses append co-author trailers,
agents narrate their own process, unrelated files ride along in a `git add -A`,
and a ticketless fix acquires an apologetic `(no-issue)` marker that means
nothing to anybody. This skill holds the line on all four.

## Step 0 — Read before you write

Never draft a message from the conversation alone; the working tree is the source
of truth and the repo's own log outranks these defaults.

```bash
git status --short
git diff                      # unstaged
git diff --cached             # already staged
git log -20 --oneline
```

Two overrides to look for, in this order:

1. **A commitlint config** — `commitlint.config.{js,cjs,mjs,ts}`, `.commitlintrc*`,
   or a `commitlint` key in `package.json`. If one exists it is the law: read it
   and satisfy it. A message this skill would happily write can still be rejected
   at push time by the repo's own CI, and rewriting published history to fix that
   is far more expensive than reading a config file now.
2. **The repo's lived style** — `CONTRIBUTING.md`, `AGENTS.md`, `CLAUDE.md`, and
   the last twenty subjects. If the project writes `[COD-123] subject` with a
   `ticket:` line, write that. Matching what the repo already does beats importing
   a convention it never adopted.

Everything below is what to do when the repo states nothing.

## Step 1 — Resolve the ticket, and accept that there may not be one

Look in this order and stop at the first hit:

1. **The invocation argument** — `/commit COD-123`.
2. **The branch name** — `feature/COD-123-add-webhooks`, `COD-123-fix`,
   `fix/cod-123`. Take the first token matching `[A-Z][A-Z0-9]+-\d+` (upper-case
   it). Say in one line which ticket you inferred and from where, so a wrong guess
   is cheap to correct.
3. **`.dev-flow/config.json`** — `tracker.ticketIdPattern` / `tracker.ticketPrefix`
   tell you what a ticket id looks like in this repo, which makes step 2 reliable
   instead of a guess. A bare number in the invocation (`/commit 123`) expands
   against `ticketPrefix`.

**No ticket found is a normal, complete outcome — not a problem to solve.** Do
not ask the user for one, do not go looking in the tracker, do not invent a
placeholder. Write the commit as though tickets were not a thing in this repo:

- No `Refs:` trailer.
- No `(no-issue)`, `(no-ticket)`, `NO-JIRA`, `Refs: none`, `Refs: N/A`.
- No sentence in the body explaining that there is no ticket.

A marker announcing an absence is worse than the absence: it adds a token every
reader has to decode and every release-note generator has to strip, to convey
exactly nothing. A ticketless commit that simply reads `fix(web): clarify the
stop controls on running cards` is complete as it stands.

## Step 2 — Group the work into commits

Structuring the change is the hard part; the wording is the easy part.

- **One concern per commit.** If the subject needs the word "and", it is two
  commits.
- **Small and single-purpose stays one commit** — a bug fix plus its tests, or
  roughly five files or fewer. Splitting that is ceremony, not clarity.
- **Split only genuinely independent concerns**, and order them by dependency:
  schema, types and helpers before the callers and components that consume them.
  A reviewer stepping through the commits should watch the feature get built, not
  reassemble it.
- **A refactor that also adds a feature is two commits**, even when the files
  overlap.
- **When the repo squash-merges** (`git config` or the repo's PR settings say so,
  and most Trau-managed repos do), splitting is discarded at merge time — make one
  commit and put the structure in the body instead.

## Step 3 — Write the message

With a ticket:

```
<type>(<scope>): <subject>

<optional body>

Refs: COD-123
```

Without a ticket — the same message with the trailer and its blank line simply
absent:

```
<type>(<scope>): <subject>

<optional body>
```

**Type** — one of `feat`, `fix`, `refactor`, `docs`, `style`, `test`, `chore`.
Pick what the change is, not what it feels like: a large diff is not a `feat`, and
a `fix` that only moves code is a `refactor`. (`epic(<TICKET>)` also appears in
Trau logs; that one is generated by the loop when it merges an epic, not written
by hand.)

**Scope** — optional, and useful when it names a real area: `auth`, `api`,
`web`, `release`, `config`. Omit it for cross-cutting changes rather than
inventing a bucket.

**Subject**
- Imperative mood: "add password reset", never "added" or "adds".
- Starts lower-case, because it continues the `type(scope): ` prefix rather than
  starting a sentence. The exception is a word that is capitalized anywhere it
  appears — a proper noun or an acronym: `feat(api): PostgreSQL lane databases…`
  stays as it is.
- Under 72 characters, and no trailing period.
- States the change, not the ticket. The id belongs in the trailer; a subject
  that opens with `COD-123:` spends its most valuable characters on a string the
  trailer already carries.

**Body** — optional, and worth writing exactly when the subject cannot carry the
whole story: a non-obvious failure, a chain of causes, several commits' worth of
structure squashed into one. Skip it entirely when the subject says enough.
- Wrap at about 100 characters.
- One idea per sentence, active voice, and the same word for the same thing every
  time. Trau writes its prose in ASD-STE100 Simplified Technical English, and a
  body that keeps to that reads the same to everyone on a mixed-language team.
- Say what changed and what it fixes — the concrete failure, the wrong output,
  the gate that was red. The deeper *why* lives in the ticket; that is what the
  trailer is for. With no ticket, a body carrying that context matters more,
  since nothing else holds it.
- Do not narrate the diff line by line. `git show` already does that better.

**Trailer** — `Refs: <TICKET>` on its own line after a blank line, and only when
a ticket was resolved in Step 1. Some repos use `Ticket:` or `Closes:`; match
what Step 0 found. When the work was carved out of an epic or parent ticket, name
the parent the rest of the delivery names — the branch and PR title point at the
same key.

## Step 4 — Stage and commit

Stage **by name**, never `git add -A` or `git add .`:

```bash
git add internal/pipeline/commitlint.go internal/pipeline/commitlint_gate_test.go
```

A blanket add is how `.env` files, credentials, build output, scratch scripts and
half of somebody else's in-progress work end up in the history. Everything you
stage must be part of the concern named in the subject; anything else stays in
the working tree, and untracked files that look like secrets (`.env`,
`credentials.json`, `*.pem`) do not get committed at all — say you skipped them.

Write the message with a heredoc so the formatting survives:

```bash
git commit -F - <<'EOF'
fix(config): isolate config tests from inherited environment overrides

Refs: COD-2502
EOF
```

If a pre-commit hook fails, the commit did not happen. Fix what the hook flagged,
re-stage, and make a **new** commit — never `--no-verify`, and never `--amend`
onto a commit that already exists for a different reason. The hook is usually the
same gate the repo's CI runs, so bypassing it just moves the failure downstream.

## Step 5 — Report and stop

Print one line per commit — short sha and subject — and stop there. This skill
commits; it does not push, does not open or update a PR, does not tag, and does
not move a tracker status. Those are dev-flow's job, or the user's. If the user
wants a push, they will ask.

## Hard restrictions

- **No AI or assistant attribution, anywhere in the message.** No
  `Co-authored-by: Claude`, no `Co-Authored-By:` variant, no `Claude-Session:`
  line, no `🤖 Generated with Claude Code`, no "written with an assistant" in the
  body. Strip them if your environment adds them by default — for Claude Code
  that is an `attribution` block in `settings.json`, on unless someone turned it
  off:

  ```json
  "attribution": { "commit": "", "sessionUrl": false }
  ```

  `commit: ""` drops the co-author trailer and `sessionUrl: false` drops the
  `Claude-Session:` link, which is a separate switch and survives on its own.
  (The older `includeCoAuthoredBy: false` still works but is deprecated, and it
  never covered the session link.) Prose alone cannot suppress a trailer the
  harness appends, so read `git log -1` after the first commit of a session and
  fix the setting once rather than fighting it every time. The reason is narrow
  and practical: these lines are noise to every human who reads the log for the
  next decade, and they end up quoted verbatim in generated release notes.
- **No editorializing.** "finally fix this annoying bug" is `fix(...)`. State
  what happened; the log is a record, not a mood.
- **No meta-commentary about the process** — which agent phase produced the
  change, how many attempts it took, that verification passed. None of it helps
  the next reader.
- **Never rewrite published history to fix a message.** If a bad message is
  already on the remote's base branch, leave it and say so. Only commits that
  have not left this machine are free to reword.

## Examples

Ticket, no body — the common case:

```
feat(web): repaint the theme palette when the active project changes

Refs: COD-2443
```

No ticket, and no trace of one:

```
fix(web): clarify the stop controls and compact running cards
```

Ticket plus a body, where the failure is not obvious from the subject:

```
fix(hubdb): renumber the worktree migration so a hub database still opens

Two epics each added a version-91 migration, so every hub database open
failed with "migrations 0091_checkout_apps.sql and 0091_worktree_db.sql
share version 91". The runner tracks applied migrations by key, not by
number, so renumbering the later file to 0092 is safe for databases that
already ran it.

Refs: COD-2470
```

No ticket, with the body carrying the context the ticket would have held:

```
chore(git): ignore the local agent directory

The directory holds symlinks into an already-ignored tree, and the skills
themselves are pinned by content hash in the tracked lockfile, so the
installed copies are build output rather than source.
```

Two commits, dependency-ordered, from one piece of work:

```
refactor(msgtmpl): extract the ticket key resolution into one helper

Refs: COD-1180
```
```
feat(pipeline): name the origin ticket in the commit when a slice has one

Refs: COD-1180
```

## Pre-flight checklist

Before each `git commit`:

1. The repo's own convention (commitlint config, `CONTRIBUTING.md`, the last
   twenty subjects) was read and wins over these defaults.
2. Every staged file belongs to the concern in the subject, and was staged by
   name.
3. The subject is imperative, lower-case, under 72 characters, with no trailing
   period and no ticket id.
4. `Refs:` is present exactly when a ticket was resolved — and when none was,
   nothing anywhere in the message refers to a ticket, its absence, or a
   placeholder for one.
5. No co-author trailer, session link, generation banner, or any other mention of
   AI authorship.
6. Nothing is pushed.
