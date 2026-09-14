# Skill authoring in Plastic

The general standard for authoring skills, agents, and hooks is the `skill-creating` skill, and the eval method is the `skill-evaluating` skill. Both live in [zalom/agent-skills](https://github.com/zalom/agent-skills):

```sh
claude plugin marketplace add zalom/agent-skills
claude plugin install skill-creating@zalom-skills
claude plugin install skill-evaluating@zalom-skills
```

This page keeps only the rules for Plastic's own tree. Read it alongside those skills when a skill, agent, or hook ships with Plastic.

## Names

The `plastic-` prefix is reserved for skills and hooks that Plastic itself ships. Doctor's ownership check (`stray_skills`) and the installer's purge both key off the prefix, so a skill authored outside Plastic's tree takes a different name.

## Defaults first

Plastic stands on its own. Skills and agents use Plastic's own defaults, and an external skill, such as `superpowers:*`, is opt-in and never load-bearing.

- **Default to Plastic, delegate by exception.** Name the Plastic-native path as the default. Delegate to an external skill only when it is available in the harness or the user explicitly asks for it. A user without that plugin still gets the core behavior.
- **Phrase external skills as enhancements.** Write "use Plastic's native X by default; if `superpowers:<skill>` is available, or the user prefers it, delegate to it", never "delegate to `superpowers:<skill>`" as the only path.
- **Optional dependencies detect, then degrade.** `qmd` is the reference shape: `scripts/lib/qmd_sync.rb` detects the binary first, and every verb of `scripts/qmd-sync` no-ops cleanly when it is absent. Optional CLIs and MCP servers follow the same detect-then-skip pattern, so a missing tool never crashes a session.
- **Legitimate hard dependencies are exempt.** Ruby, Node, git, and POSIX tools are the cost of running Plastic, not silent coupling. The rule targets accidental dependence on external skills doing work Plastic should do itself.

## Scripts

- Scripts ship in Ruby, and a worked example that shows a script shows Ruby.
- A shell script runs under macOS `/bin/bash` 3.2: no `bash` 4.x features (no associative arrays, no `mapfile`, no `${var^^}`), and no heredocs inside `$(...)`.
- `scripts/skill-lint` checks the skill tree mechanically: `ruby scripts/skill-lint --skills-dir skills`.

## Hooks

Plastic registers its hooks in `hooks/hooks.json`. Before you author a new hook, read an existing one of the same shape: `scripts/hook-session-start` for SessionStart, or `scripts/hook-savepoint` for PreCompact.

## Dashes

User-facing docs (README, `docs/`, `AGENTS.md`, `CLAUDE.md`) never use em dashes or en dashes, and newly authored skill text avoids them. Existing internal files and the sanctioned template output, the INDEX line shape in `templates/index.md`, are not violations.

## Intent structure checks

Use these checks with the `skill-evaluating` skill when an eval covers intent compliance.

| Check | Pass criteria |
|---|---|
| Intent file exists | `{ID}--{slug}.md` is present in the intent directory |
| Frontmatter complete | `id`, `intent`, `sources`, `chain`, `created`, `author`, and `tags` are present |
| ID format | Digits and letters alternate, in the Luhmann style |
| Directory name | `{ID}--{slug}`, with a short kebab-case slug |
| Placeholders | `scripts/new-intent` writes `spec.md`, `plan.md`, `checklist.md`, and `outcome.md` at birth with `<!-- plastic:placeholder -->` as the first line, so a stage counts as reached only when its file has lost that line, never because the file exists |
| Graph delivery | A graph delivery adds `graph.md` and `nodes/` next to a real `plan.md`, and its `checklist.md` can stay a placeholder |
| Outcome | A delivered or abandoned intent has a real `outcome.md` |
| Insights append-only | The `## Insights` section only grows |
