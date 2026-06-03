# Commit conventions

Use these conventions when crafting commits directly inside this skill (Step 6) — i.e. when `commitSkill.userInvokedOnly` is not set, or no commit skill is configured for the project.

**First, look at the project's existing commits.** If `git log -20 --oneline` shows a different style (different format, different types, different trailer), match what the project does. These defaults are the fallback — they shouldn't override a project's lived convention.

## Logical grouping

The hardest part of committing well is structuring the work, not writing the messages. Before staging anything:

- **One concern per commit.** If a commit message needs the word "and", it's probably two commits.
- **Order by dependency.** Foundational changes first (schema, types, helpers), then the changes that consume them (callers, components, routes). A reviewer reading the PR commit-by-commit should be able to follow the build-up of the feature.
- **Separate refactors, features, and fixes** into distinct commits even when they touch overlapping files. A "refactor that also adds a feature" is two commits.

If you're using Serena MCP (or another semantic-edit tool), prefer it for the staging step — symbol-level edits make atomic commits much easier than line-range edits.

## Format

Conventional Commits style is the default:

```
<type>(<scope>): <subject>

[optional body]

Refs: <TICKET-ID>
```

**Types:** `feat`, `fix`, `refactor`, `docs`, `style`, `test`, `chore`. Use what matches the change; don't inflate `refactor` to `feat` just because the diff is large.

**Scope** is optional but useful — usually a top-level area of the codebase (`auth`, `api`, `orders`, `ui`). Skip it for cross-cutting changes.

**Subject:**
- Imperative mood: "add password reset", not "added password reset" or "adds password reset".
- Under 72 characters.
- No trailing period.

**Body** (optional):
- Wrap at 100 characters.
- State *what* changed and *how*, not *why*. The "why" lives in the ticket — that's what the `Refs:` trailer is for.
- Skip the body if the subject says enough on its own. Don't pad.

**Trailer:**
- `Refs: <TICKET-ID>` when a ticket exists.
- Some teams use `Ticket:` or `Closes:` instead — match the project.
- Skip the trailer entirely in no-tracker mode.

## Examples

```
feat(auth): add password reset functionality

Refs: MLG-123
```

```
fix(api): handle null response in user endpoint

The /me endpoint returned null when the session cookie was expired
but technically valid; downstream consumers crashed on .name access.

Refs: MLG-99
```

```
refactor(orders): extract shipping calculation to service
```
(no body, no trailer — small refactor, no-ticket exception)

## Hard restrictions

- **Never mention AI tools, assistants, or code generation** in commit messages. No `Co-Authored-By: Claude`, no "generated with", no meta-commentary about the development process. These are noise to every other developer who reads `git log` for the next decade.
- **Don't editorialize.** "Finally fixes this annoying bug" → just `fix(...)`. State facts.
- **Don't bundle unrelated changes "for convenience".** If a commit message has three sentences each describing a different change, split it.

## When to defer to user invocation

If config has `commitSkill.userInvokedOnly: true`:
- Do **not** craft commits directly.
- Pause and tell the user: "Implementation is ready. Please run `/{commitSkill.name} {TICKET-ID}` yourself."
- The gate exists deliberately (usually to enforce explicit human authorization before committing) — respect it. Don't try to work around it with a hand-crafted `git commit`.
