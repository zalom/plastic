# Design: `plastic:doctor`

> Unified diagnostics command that checks a Plastic installation for health
> issues and offers fixes. Merges intents 14a (convention enforcement) and
> 22 (doctor diagnostics).

## Architecture

Three files, agent as glue:

| File | Role |
|------|------|
| `scripts/doctor.rb` | Diagnostic engine. Runs checks, outputs JSON to stdout. Distributed to `~/.plastic/scripts/doctor.rb` on install. |
| `skills/doctor/report.md` | Markdown template with placeholders. Any model fills it from the JSON output. |
| `skills/doctor/SKILL.md` | Orchestration: run script, parse JSON, fill template, show to user, offer fixes. |

### Design principles

- **Ruby script** — deterministic fact-checker. No markdown generation, no agent
  awareness. Outputs structured JSON only. Stays focused and testable.
- **Markdown template** — presentation layer. Contains placeholders that any
  model (including weak open-source LLMs) can fill from the JSON output.
  Find-and-replace, not transformation.
- **SKILL.md** — tells the agent what to do. The agent is glue: run script,
  read JSON, fill template, show report, offer fixes for fixable items.
- **Agent-agnostic** — Plastic is not Claude Code-specific. The template
  ensures consistent reporting regardless of which LLM drives the session.

## Check categories

### 1. `global_store` — Global store health

| Check | Severity | Fixable | What it verifies |
|-------|----------|---------|------------------|
| `index_exists` | fail | yes | `~/.plastic/INDEX.md` exists |
| `index_sections` | fail | yes | INDEX.md has all 5 required sections: Active, Future, Clusters, Abandoned, Completed |
| `orphaned_intents` | warn | yes | Intents in `store/` directory not referenced in INDEX.md |
| `ghost_references` | warn | yes | Entries in INDEX.md pointing to non-existent intent directories |

### 2. `conventions` — Convention compliance

| Check | Severity | Fixable | What it verifies |
|-------|----------|---------|------------------|
| `intent_dirname` | warn | yes | Intent directories follow `{ID}--{slug}/` format |
| `intent_filename` | warn | yes | Primary intent file matches `{ID}--{slug}.md` inside its directory |
| `frontmatter_fields` | warn | no | Required frontmatter fields present: id, intent, sources, chain, created, author, tags |

### 3. `agent_registration` — Agent registration health

| Check | Severity | Fixable | What it verifies |
|-------|----------|---------|------------------|
| `hooks_exist` | fail | yes | Hook scripts exist in agent's hooks directory (e.g., `~/.claude/hooks/plastic-*`) |
| `hooks_executable` | fail | yes | All hook scripts have executable permission |
| `hooks_registered` | fail | yes | Agent's settings.json has all Plastic hook events registered (SessionStart, PreCompact, PostToolUse, UserPromptSubmit) |
| `skills_exist` | fail | yes | Skill files exist in agent's skills directory (e.g., `~/.claude/skills/plastic/`) |

### 4. `core_files` — Core files integrity

| Check | Severity | Fixable | What it verifies |
|-------|----------|---------|------------------|
| `plastic_md` | fail | yes | `~/.plastic/PLASTIC.md` exists |
| `version_file` | fail | yes | `~/.plastic/VERSION` exists |
| `scripts_present` | fail | yes | Required scripts exist in `~/.plastic/scripts/` |
| `scripts_executable` | fail | yes | All scripts in `~/.plastic/scripts/` have executable permission |
| `version_match` | warn | no | `~/.plastic/VERSION` matches agent-side VERSION file |

### 5. `project_stores` — Project store health

| Check | Severity | Fixable | What it verifies |
|-------|----------|---------|------------------|
| `project_dir_exists` | warn | yes | Each project in `projects.yml` has a store dir under `~/.plastic/projects/{slug}/` |
| `project_index` | warn | yes | Each project store has an INDEX.md |
| `cross_references` | warn | no | Global parent intent has `chain` linking to project and `project-{slug}` tag |

### 6. `deprecations` — Active deprecations

| Check | Severity | Fixable | What it verifies |
|-------|----------|---------|------------------|
| `active_deprecations` | warn | no | Deprecations from `deprecations.yml` that haven't been addressed |

## Severity levels

- **pass** — all good
- **warn** — non-blocking; does NOT prevent Plastic from operating normally but
  affects user experience (e.g., stale deprecation, orphaned intents, missing
  optional config)
- **fail** — blocking; DOES prevent Plastic from operating normally (broken
  hooks, missing scripts, missing skills/agents)

## JSON output schema

```json
{
  "version": "1.0.0-alpha.5",
  "timestamp": "2026-06-08T14:30:00Z",
  "status": "fail | warn | pass",
  "agent": "claude",
  "checks": [
    {
      "category": "agent_registration",
      "name": "hooks_executable",
      "status": "fail",
      "message": "2 hook scripts not executable",
      "details": [
        "~/.claude/hooks/plastic-session-start",
        "~/.claude/hooks/plastic-gate-check"
      ],
      "fixable": true,
      "fix_hint": "chmod +x on the listed files"
    }
  ],
  "summary": {
    "pass": 10,
    "warn": 2,
    "fail": 1,
    "total": 13
  }
}
```

### Field definitions

- `version` — installed Plastic version from `~/.plastic/VERSION`
- `timestamp` — ISO 8601 UTC time of the check run
- `status` — top-level roll-up: `fail` if any check fails, `warn` if only
  warnings, `pass` if all checks pass
- `agent` — which agent was checked (from `--agent` flag)
- `checks[]` — array of individual check results:
  - `category` — one of the 6 categories above
  - `name` — unique check identifier within category
  - `status` — `pass`, `warn`, or `fail`
  - `message` — human-readable one-line summary
  - `details` — optional array of specific items (file paths, intent IDs, etc.)
  - `fixable` — whether the agent can fix this automatically
  - `fix_hint` — short description of what the fix would do (present on warn
    and fail regardless of fixable — guides the agent or user on resolution)
- `summary` — count of checks by status

## Script interface

```
ruby ~/.plastic/scripts/doctor.rb [--agent claude|codex|hermes]
```

- Default agent: `claude`
- Output: JSON to stdout
- Exit codes: 0 (all pass), 1 (warnings only), 2 (failures present)
- No side effects — read-only, never modifies files

## Entry points

1. **On-demand** — user invokes `/plastic:doctor`
2. **Post-update** — `plastic:update` skill invokes doctor automatically after
   the installer finishes. The update skill reads the JSON output and presents
   findings inline.

## Agent flow (SKILL.md orchestration)

1. Run `ruby ~/.plastic/scripts/doctor.rb --agent claude`
2. Parse JSON from stdout
3. Read `report.md` template, fill placeholders from JSON
4. Present filled report to user
5. If any checks have `fixable: true` — offer to fix (grouped by category)
6. Apply fixes the user approves
7. Re-run doctor to verify fixes resolved the issues

## Report template (report.md)

The template uses simple placeholders that any model can fill:

- `{{status_icon}}` — overall status emoji
- `{{version}}` — Plastic version
- `{{summary}}` — pass/warn/fail counts
- `{{category_sections}}` — one section per category with its checks
- `{{fixable_section}}` — list of fixable items with fix descriptions

The template is a complete markdown document — the agent's job is substitution,
not composition.

## Distribution

`scripts/doctor.rb` is added to the installer's `core_files` hash in
`scripts/install.rb`, so it gets distributed to `~/.plastic/scripts/doctor.rb`
on install/update. The skill files (`skills/doctor/SKILL.md` and
`skills/doctor/report.md`) are distributed to the agent directory as part of
the existing skill copy mechanism.

## Testing

`test/doctor_test.rb` — unit tests for the Ruby script:
- Each check category has tests for pass, warn, and fail scenarios
- Tests use a temporary directory structure (not the real `~/.plastic/`)
- JSON output is parsed and assertions made on structure and content
- Exit codes verified
