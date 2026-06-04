# RomkaLTU / skills

Shared agent skills for the team. Works with any agent that loads Markdown skills
(Claude Code, and others via the symlink fallback below).

## Skills

| Skill | What it does |
|-------|--------------|
| **dev-flow** | Ticket-driven git workflow end-to-end — branch from base → tie to a ticket (Linear / Jira / GitHub Issues / none) → name branches & commits → open the PR against the right base → move the ticket through In Progress / In Review / Done. Also kicks off work from a plan/PRD/todo, and self-initializes its config. Per-repo settings live at `.dev-flow/config.json`. |

## Install — Skills CLI (recommended)

You already use this for your other skills; nothing new to learn.

```bash
npx skills add RomkaLTU/skills@dev-flow -g -y
```

`-g` installs globally into **every** agent the CLI detects. If you hit
`<agent> does not support global skill installation` (e.g. PromptScript, which is
project-only), either scope the install to a global-capable agent:

```bash
npx skills add RomkaLTU/skills@dev-flow -g -a claude-code -y   # -a is repeatable
```

or install project-locally by dropping `-g` (run from the repo root):

```bash
npx skills add RomkaLTU/skills@dev-flow -y
```

Keeping current:

```bash
npx skills check      # show what's out of date
npx skills update     # update everything
```

## Install — symlink fallback (no Skills CLI)

For teammates or agents that don't use `npx skills`. Idempotent — **re-run to update**.

```bash
curl -fsSL https://raw.githubusercontent.com/RomkaLTU/skills/main/install.sh | bash -s -- dev-flow
```

or clone and run:

```bash
git clone https://github.com/RomkaLTU/skills.git
./skills/install.sh dev-flow
```

By default it symlinks into `~/.claude/skills`. For another agent, point it elsewhere:

```bash
SKILL_TARGET_DIRS="$HOME/.cursor/skills" ./install.sh dev-flow
```

## Repo layout

```
skills/<name>/SKILL.md      # entry point the Skills CLI installs (owner/repo@<name>)
skills/<name>/references/   # progressive-disclosure docs, loaded on demand
skills/<name>/assets/       # templates / example configs
install.sh                  # no-CLI symlink installer/updater
```

## Contributing

Edit a skill under `skills/<name>/`, bump its `version` in `SKILL.md` frontmatter,
add a `CHANGELOG.md` entry, and open a PR. Once merged, teammates pick it up with
`npx skills update` (or by re-running `install.sh`).
