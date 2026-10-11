# Harness Adapters

How Plastic reaches each agent harness: the registry, how a hook names its session and its
harness, the doctor of each harness, and what Plastic installs into each one.

## Purpose and use model

Plastic is for reasoning agents, in two shapes:

1. A user working directly inside a reasoning agent, using Plastic as the operating scaffold
   for their own thinking and delivery.
2. A user instructing a reasoning agent to use Plastic to deliver the user's intents,
   producing a human-legible system of intents, specs, plans, and outcomes.

Both shapes assume a reasoning agent on the other side. Plastic targets reasoning agents only.
It is not a library you call from ordinary application code, and it does not target
non-reasoning automation. A harness adapter is the glue that makes one specific agent harness
load Plastic's conventions, honor its decisions, and record its work.

## The harness registry

Plastic ships one entry for each harness it knows, in `scripts/lib/plastic/harnesses.rb`:

| Field | Claude Code | Codex | Hermes |
| ----- | ----------- | ----- | ------ |
| Name | `claude-code` | `codex` | `hermes` |
| Session variables | `CLAUDE_CODE_SESSION_ID` | `CODEX_THREAD_ID`, `CODEX_SESSION_ID` | none |
| Transcript path | under `.claude/projects/` | under `.codex/sessions/` | none |
| Process name | `claude` | `codex` | none |
| Event field only it writes | none | `turn_id` | none |
| Hooks | `hook start`, `hook stop`, `hook end` | `hook start`, `hook stop`, `hook end` | none |
| Folder | `.claude` | `.codex` | `.hermes` |
| Settings file | `.claude/settings.json` | `.codex/hooks.json` | none |
| Doctor checks | `Doctor::ClaudeCode` | `Doctor::Codex` | none |

The installer writes each harness's hooks from its entry, and the doctor compares the installed
hooks with it. `plastic config --harness NAME` takes only a name the registry holds. The start hook
names the harness from these fields and records it on the session row. A field an entry leaves
empty is skipped: detection never names Hermes, and the doctor has no module for it.

## How a hook names its session and its harness

A hook reads `session_id` from the event JSON on its standard input. Without one, it takes
`PLASTIC_SESSION` when that is set, and otherwise the session variable of each harness in the
registry. One id is used as it is. When one harness runs inside another, both variables are
set, and `Harnesses::Innermost` picks the inner session in this order:

1. The session whose row started last.
2. The session of the harness that the nearest ancestor process names.
3. The first id, in registry order.

The start hook names the harness once, through `Harnesses::Detection`, and records it on the
session row. Later hooks and the doctor read the harness from the row. Detection takes the
first of these steps that answers:

| Step | It names the harness when |
| ---- | ------------------------- |
| Event | The event's `harness` field names a registered harness, or the event carries a field only one harness writes, such as Codex's `turn_id` |
| Session variable | A harness's session variable equals the event's `session_id` |
| Transcript | The event's `transcript_path` matches a harness's transcript path |
| Process | The nearest ancestor process has a harness's process name |
| `AI_AGENT` | The variable names a harness the registry lacks |

When no step answers, the row records `unknown`. No environment variable carries the harness,
because a variable one harness sets reaches every harness started from its shell.

`Harnesses::Processes` reads the ancestor processes from the `/proc` folder, so the process
steps answer on Linux only. On macOS both find nothing: detection goes on to `AI_AGENT`, and
`Harnesses::Innermost` goes on to the first id. Plastic starts no process to ask.

When a session starts fresh, `plastic hook start` runs the doctor in its own process for a
registered harness, and prints one line naming `plastic doctor` only when a check fails. A name
on the row that the registry lacks, `unknown` or the name `AI_AGENT` gave, has no doctor. For
it, the start hook prints one line that names the session and the name on its row, and ends by
naming `plastic doctor --harness` with the registered harnesses.

## The doctor of each harness

`plastic doctor` runs `Doctor::Core` for every harness, then the module that `Doctor::HARNESSES`
names for the harness. `--harness NAME` picks the module. Without it, the doctor takes the
harness on the session row, then the one a session variable equal to the session names. When
neither names a registered harness, it exits 2 and asks for `--harness` with the registered
names.

| Module | It checks |
| ------ | --------- |
| `Doctor::Core` | The version record, the parts of the installation, the `sqlite3` gem, the machine database, the global store, `PLASTIC.md`, and each registered project's store and `AGENTS.md` |
| `Doctor::ClaudeCode` | The record `~/.claude/plastic/VERSION`, each hook event in `~/.claude/settings.json`, the import of `PLASTIC.md` in `~/.claude/CLAUDE.md`, and each project's `CLAUDE.md` importing `@AGENTS.md` |
| `Doctor::Codex` | The record `~/.agents/plastic/VERSION`, `CODEX_HOME`, each hook in `~/.codex/hooks.json`, `~/.codex/AGENTS.md` naming `PLASTIC.md`, and a hook trust row |

Each check is a `Doctor::Check`: a label, a value that starts with `ok` or names the finding,
and the repair. The doctor only detects: it reads files and opens the databases read-only. A
repair is a command that owns that kind of change, such as `plastic install --reinstall`, or a
line to add to a file, and the doctor never runs it. `Doctor::DatabaseCheck` opens a database read-only and compares its tables with
the tables its schema creates. A hook passes when every file its command names exists and is
executable. `CodexHookCommand` parses each Codex hook command as shell words without running
it, and accepts the installer's `env -u RUBYOPT` prefix and `|| true` suffix. The doctor does
not read Codex's trust records: its hook trust row says that trust is not verified and asks the
person to review the hooks in Codex's `/hooks`. That row has no repair and does not change the
exit code. A new harness adds one class with a public `checks` and one row in `HARNESSES`.

## Instruction sections

Plastic writes one marked section into each harness's instruction file. The install record
lists each section with its markers, and the uninstall removes only the section.

| Harness | File | Markers | Body |
| ------- | ---- | ------- | ---- |
| Claude Code | `~/.claude/CLAUDE.md` | `<!-- BEGIN PLASTIC COMPACT hash:... -->` and `<!-- END PLASTIC COMPACT -->` | `CompactInstructions::BODY`: one sentence and the import `@~/.plastic/PLASTIC.md` |
| Codex | `~/.codex/AGENTS.md` | `<!-- BEGIN PLASTIC INTEGRATION ... -->` and `<!-- END PLASTIC INTEGRATION -->` | Plastic's standing conventions, naming `PLASTIC.md` |
| Hermes | none | none | none |

The import names the installed copy under the Plastic home, because a bare `@PLASTIC.md` would
resolve against `~/.claude`. The two harnesses use different markers because the two files can
be one file: a person who links `~/.claude/CLAUDE.md` to `~/.codex/AGENTS.md` keeps both
sections. Writing and removing a section resolve a link to its target first, so a linked file
stays a link.

## Agent files

The installer copies each role file of `agents/` into every harness that reads agents.

| Harness | Folder | File |
| ------- | ------ | ---- |
| Claude Code | `~/.claude/agents/` | `NAME.md`, copied |
| Codex | `~/.codex/agents/` | `NAME.toml`, rendered with the name, the description, the model fields and the instructions |
| Hermes | `~/.hermes/agents/` | `NAME.md`, copied |

A model or an effort set for a harness in `config.yml` rewrites that agent's model line for
that harness only. With `advisor.enabled: false`, the two advisor agents are not installed.

`plastic init` counts a harness as found when its folder, `.claude`, `.codex` or `.hermes`, is in
the home, or its program, `claude` or `codex`, is on the `PATH`. Hermes names no program, so
only its folder finds it. It writes only into a harness
the registry holds.

## Install records

Each install into a harness writes one record, `~/.plastic/installations/NAME.json`, with the
harness name as `NAME`. `plastic uninstall` reads it and removes exactly what it lists.

| Field | What it lists |
| ----- | ------------- |
| `harness` | The registry name of the harness |
| `version` | The Plastic version that wrote it |
| `roots` | The folders the files must sit under; a file outside them is never removed |
| `files` | Each file Plastic wrote |
| `folders` | Each folder Plastic made, removed once it is empty |
| `settings` | The settings file that holds the hooks |
| `hooks` | Each hook entry Plastic wrote, as its event and its command |
| `status_line` | The status line Plastic set, and the one it replaced |
| `permissions` | Each permission entry Plastic added |
| `sections` | Each instruction file that holds a Plastic section, with the section's begin and end markers |

The uninstall removes only these entries from the settings file and these sections from the
instruction files, so the person's own entries and text stay. Only the main session runs
Plastic's hooks: no record lists a SubagentStart or a SubagentStop entry.

## Harness support

| Harness | Install | Instructions | Hooks | Status line | Agents |
| ------- | ------- | ------------ | ----- | ----------- | ------ |
| Claude Code | `install.sh`, then `plastic init` | The import section in `~/.claude/CLAUDE.md` | `hook start`, `hook stop` and `hook end`, plus the update check at session start, in `~/.claude/settings.json` | Yes, unless `statusline` is off in `config.yml` | `~/.claude/agents/` |
| Codex CLI | `install.sh`, then `plastic init` | The section in `~/.codex/AGENTS.md` | `hook start`, `hook stop` and `hook end` in `~/.codex/hooks.json` | No | `~/.codex/agents/` |
| Hermes | `install.sh`, then `plastic init` | None | None | No | `~/.hermes/agents/` |

So Claude Code gets three kernel hooks and the update check through `settings.json`. Each
harness keeps its version record in its own folder: `~/.claude/plastic/VERSION`,
`~/.agents/plastic/VERSION` and `~/.hermes/plastic/VERSION`.

Codex reads hooks registered at user scope, in `~/.codex/hooks.json`. Codex runs a hook only
after the person trusts its command in `/hooks`, and a changed command needs that trust again.
After an install, the installer names each Codex hook whose command changed. Plastic does not
write `~/.codex/config.toml`.

Hermes gets the agents and its version record, and no hooks and no instruction section, so
Plastic records nothing of a Hermes session.
