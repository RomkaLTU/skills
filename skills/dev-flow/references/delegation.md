# Cheaper-model delegation

Some steps in this workflow are high-volume but low-judgment — drafting a commit message is the
canonical one. The `delegation` config block routes those steps to a faster/cheaper model so the
expensive main-session model isn't spent on boilerplate. This reference defines the contract: when
delegation applies, how to pick a mechanism in whatever host agent is running, what to send the
delegate, and how to validate what comes back.

Currently one step is delegable: **commit-message drafting** (Step 6, and the escape hatch when it
commits). Everything else about committing stays with the main agent.

## Config

```json
"delegation": {
  "commitMessage": {
    "enabled": true,                 // default true when the block exists; false disables it
    "models": {                      // key = host-agent family, value = that agent's model id
      "claude": "haiku",             // Claude Code — subagent model alias or full model id
      "codex": "gpt-5.1-codex-mini", // Codex CLI — model for `codex exec -m`
      "cursor": "composer-1"         // Cursor — model for a subagent / `cursor-agent --model`
    }
  }
}
```

The `models` keys are open-ended — `opencode`, `gemini`, or any other family the team uses is fine;
the value is whatever model identifier *that* agent accepts. You know which agent you are: pick the
matching key. **No block, `enabled: false`, or no key for your family → draft inline as always, in
silence.** Delegation is a pure optimization; its absence is never worth a remark.

## What is — and isn't — delegated

- **Delegated:** the commit message *text*. Nothing else.
- **Not delegated:** commit *planning* (how to split work into atomic, dependency-ordered commits —
  that's the judgment-heavy part and stays with you), staging, running `git commit`, and every
  `handoff` gate from Step 6. The delegate never executes git commands and never sees write access.
- **Not applicable:** when the project's own commit skill runs the commit (`handoff.commit: false`
  with `commitSkill.name` set), that skill owns the message — delegation only covers messages *you*
  draft.
- **Skip silently for trivial diffs** (a one-liner, a typo fix): the delegation round-trip costs
  more than it saves. Use your judgment; when in doubt, drafting inline is always correct.

## Resolve the mechanism

Pick the first that works in the host you're running in:

1. **Native subagent with a model override.** Claude Code: spawn the commit-message task via the
   Task/Agent tool with the configured model (e.g. `model: "haiku"`); a project-defined subagent
   (e.g. `.claude/agents/commit-writer.md` with `model:` frontmatter) also qualifies — prefer it if
   the project ships one. Other hosts with equivalent subagent + model-override support: same idea.
   This is the best mechanism — it bills inside the session and the subagent gets a fresh, tiny
   context instead of the whole conversation.
2. **Headless one-shot CLI.** When no native mechanism exists but a CLI is on `$PATH`
   (check with `command -v` first; flags drift — verify with `--help` if a call errors):

   ```bash
   claude -p --model <model> "<prompt>"
   codex exec -m <model> "<prompt>"
   cursor-agent -p --model <model> "<prompt>"
   ```

   Note these spawn a separate, separately-billed session — still usually a win when the configured
   model is cheap, but don't loop on it.
3. **Neither available** → draft inline. Mention it once, in one line, only if the user explicitly
   configured delegation ("delegation is configured but no subagent/CLI mechanism is available
   here — drafting inline"), then proceed normally.

## Build the payload

The delegate has none of your conversation context. Give it everything it needs and nothing more:

- **The diff for this commit** — `git diff --cached` once staged, or `git diff -- <files>` for the
  planned file set. For giant diffs, send `git diff --stat` plus the meaningful hunks; never dump a
  lockfile.
- **Style sample** — `git log -10 --oneline`, plus one or two full messages if the project uses
  bodies/trailers, so the delegate matches the lived convention.
- **The ticket id** and the trailer form in use (`Refs: <TICKET-ID>`, or the project's variant).
- **A condensed ruleset** from `references/commit-conventions.md`: Conventional Commits format,
  imperative mood, subject ≤ 72 chars, body wrapped at 100 and only if it adds something, and the
  hard restriction — never mention AI tools, assistants, or code generation.
- The instruction to **return only the commit message text** — no preamble, no fences, no
  commentary.

For multiple planned commits, make one delegate call per commit, each with only that commit's diff.
Small payloads keep the cheap model accurate and the messages focused.

## Validate the result

Cheap models get format wrong more often. Before using the returned message, check:

- Format matches `<type>(<scope>): <subject>` (or the project's observed style).
- Subject is imperative, ≤ 72 chars, no trailing period.
- The trailer is present when a ticket exists and absent when it doesn't.
- No AI/assistant/generation mentions, no editorializing.

If anything is off, **fix it yourself inline** — one delegation round-trip is the budget; don't
ping-pong corrections back to the delegate. If the result is unusable garbage, discard it and draft
inline.

Then use the message exactly as Step 6 dictates: present it as the suggested commit when
`handoff.commit` is true (the default), or commit with it yourself only when `handoff.commit:
false`.

## Cost and policy notes

- The diff reaches the configured model just as it would reach the main model inline. If the
  project's policy forbids sending code to a particular provider or model tier, don't configure
  that key — and if you notice a configured delegate conflicts with a stated policy, flag it
  instead of delegating.
- Model identifiers in `models` are passed through verbatim; when one is rejected by the host
  (renamed, retired), report the error and draft inline rather than guessing a substitute.
