# Plastic

Intent-driven state management for AI coding sessions.

## Stack
- Language: Ruby (scripts), JavaScript/Node.js (npm package, installer)
- Framework: npm package (CLI installer), flat personal skills
- Testing: `ruby -Itest test/*_test.rb` (Minitest)
- Source: /Users/zlatko/apps/personal/plastic
- Remote: git@github.com:zalom/plastic.git

## Defaults
- Release process: commit_and_push, github_release, npm_publish
- Version files: package.json, .claude-plugin/plugin.json, .claude-plugin/marketplace.json
- Tag format: v{{version}}
- All bash scripts must work under macOS /bin/bash 3.2 (no bash 4.x features)
- Bump all 3 version files on every fix/feature release

## Working on Plastic

Rules for any agent (or human) contributing to this repository.

### Documentation
- Keep docs in sync with the framework. When you change the architecture, the lifecycle,
  conventions, skills, hooks, templates, or harnesses, update `docs/architecture.md` and
  `docs/internals.md` in the same change.
- Keep the README light. It carries the pitch, install, and a pointer into `docs/`.
  Deeper material belongs in `docs/`.
- User-facing documents (README, `docs/`, AGENTS.md, CLAUDE.md) avoid AI tell-tale signs.
  Do not use em-dashes. Use commas, periods, parentheses, or colons. Internal store and
  intent files are exempt from this rule.

### Work
- All work flows through an intent. Move it through What, Why, How, Exec. Do not jump
  straight to code.
- Plans, specs, checklists, and outcomes live in the intent directory under `~/.plastic/`,
  never in the project tree.

### Commits and releases
- Use Conventional Commits (`feat:`, `fix:`, `docs:`, `refactor:`, `chore:`).
- Bump all version files listed in Defaults on every fix or feature release.
- Release through the `plastic-releasing` workflow (tag, GitHub release, npm publish).
- Run `ruby -Itest test/*_test.rb` and confirm green before committing code changes.
- Never push `~/.plastic/`. The global store is local-only and may contain private data.
