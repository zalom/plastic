# Harness Adapters

How a reasoning agent harness loads, honors, and records Plastic. This is the contract every
adapter fills in, the capability tiers an adapter can claim, and two worked examples (Claude
Code interactive, Codex CLI).

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

## The contract

Plastic reaches an agent across three layers. An adapter is judged on how each layer arrives
and how it is honored. Since 2.0 nothing blocks a write: conventions persuade, live state
orients, and the record hook writes down what happened.

| Layer | Load (does it arrive) | Honor (what the agent does with it) |
|---|---|---|
| L1 standing conventions | Convention docs (PLASTIC.md, AGENTS.md, CLAUDE.md) inject into the agent's context at start | The conventions frame every decision; the agent reads them as standing rules |
| L2 live state | The day ledger, the session pointer, and the active intent's stage arrive at the point of work (session event and/or spawn preamble) | The live snapshot tells the agent where it records and where it is in the cycle |
| L3 the record | The record hook fires after every file write; the capture hook on every prompt; the close hook at session end | The savepoint and day ledgers record the move; the delivery-lock lease is refreshed for an auto team |

### Lock provenance contract

Locks exist for auto teams. Every adapter passes lock provenance explicitly when it knows it.
`harness` uses the adapter's canonical value, such as `claude`, `codex`, or `hermes`; `agent`,
`model`, and `thread` use the harness's actual values. Unknown harness, role, model, or thread
values stay `Unknown`. Adapters must not infer them from transcript paths, session-id formats,
process names, or model defaults.

Provenance is descriptive. The session id remains the authorization identity, and the
`delivery.lock` file mtime remains the sole heartbeat and freshness truth. Controller,
delegate, and artifact-claim records are separate evidence and must not be collapsed into a
single worker label. The adapter registers child sessions as delegates and reports their
activity status. That status is descriptive and does not revoke the delegate session's
authorization. Plastic bounds finished or failed activity history to the 20 most recent entries.

## Skill invocation prefix

Each adapter's users invoke a Plastic skill with a different literal prefix in front of the bare
skill name (for example `plastic-doctor`). `InstallerCore::DEFAULT_AGENTS` carries this as each
entry's `skill_prefix`, the documented source both `Bridge.skill_ref` (`scripts/lib/lock.rb`) and
this table cite; the hook scripts do not read `DEFAULT_AGENTS` at runtime, so the two are
independently maintained by hand.

| Adapter | Invocation |
|---|---|
| Claude Code | `/plastic-<name>` (slash) |
| Codex CLI | `$plastic-<name>` (dollar), explicit; Codex may also select a skill implicitly by matching its `description` |
| Hermes | not yet defined (future adapter, see Roadmap below) |

## The harness-agnostic core and the Claude adapter

The intent screen (intent 316a, refined by intent 316a1) splits into two halves, named the same
way in code, docs and spec so the boundary cannot rot silently. Each file in the split carries one
of two exact header lines, and no core file may justify a choice by any one harness's behavior.

**Harness-agnostic core** — `scripts/lib/intent_screen.rb`, `scripts/lib/intent_screen_ansi.rb`,
and `scripts/intent-screen` (it holds the plain/ANSI selection, so it belongs on the core side too).
Header line: `Harness-agnostic core: no harness assumption lives here.`

**Claude adapter** — `scripts/lib/message_display.rb`, `scripts/hook-message-display`, and
`hooks/message-display`. Header line:
`Claude adapter: Claude Code only; the core is harness-agnostic.`

The only Claude-driven choice the core used to make on its own — stripping backticks and `*`/`__`
emphasis runs before text reaches a raw ANSI block, because Claude Code still Markdown-processes
`displayContent` even inside one — is now an option the adapter supplies rather than a default the
core imposes. `IntentScreenAnsi.render` takes `markdown_safe:`, defaulting to `false`: the
harness-neutral default, because the core's other renderer (`IntentScreen.render`) is itself a
Markdown surface that preserves backticks, and stripping a user's own text is a concession one
harness needs, not a service every harness needs. The Claude adapter passes `markdown_safe: true`
at its sole call site, `scripts/lib/message_display.rb`'s `finalize`.

This supersedes 316a's D6 ("Claude Code only, no Codex projection", read as an architectural
stance) with intent 316a1's D3, cross-harness architecture. The *behavior* Claude Code gets did
not change and was proven live before this split; only where the decision to strip Markdown lives
did.

`resources/evidence--harness-surfaces.md` in intent 316a1's own record carries the per-harness
display-surface matrix. This split is what makes it possible to ask honestly about a second harness.

## Harness support

| Harness | Install | Standing conventions | Live state | Record | Statusline | Subagent teams |
|---|---|---|---|---|---|---|
| Claude Code | npm, `plastic-install --claude` | native `CLAUDE.md`, plus the compact-instructions marked section injected into `~/.claude/CLAUDE.md` | six hooks through `settings.json` | post-write `record` (savepoint, lock heartbeat, day ledger) | yes | yes |
| Codex CLI | npm, `plastic-install --codex` | marked section injected into `~/.codex/AGENTS.md` | six hooks through `~/.codex/hooks.json`, all dispatched by one command | post-write `record` on `apply_patch` | no | no, a single agent walks the whole cycle |
| Hermes | npm, `plastic-install --hermes` | none | none | none | no | no |

1. Plastic installs from npm only, for every harness above (owner ruling of 2026-08-08).
   No other install path exists or is planned.
2. Hermes copies skills and agent files and wires nothing else. It is a packaging target,
   not a working adapter.
3. Codex receives its skill text with paths and command prefixes rewritten at install time
   (intent 239), so the instructions resolve on a Codex machine. Four lines still speak
   Claude Code afterward, all disclosed and none executable: four instruction lines that
   name Claude's hook launcher directory, left as they are because Codex installs no
   per-agent launchers and there is no Codex path to point at. The skill-authoring
   reference, the shared underscore fragment, and the evals fixtures that carried
   Claude paths left the installed tree in 2.0 (intent 304).
4. Codex has no statusline and no subagent dispatch. Both are gaps, not stated non-goals.
   The close hook runs on both harnesses since intent 309.

## Per-harness version truth (intent 210)

Every adapter's own installed version lives at the same uniform path,
`<agent-dir>/plastic/VERSION`, alongside its own `<agent-dir>/plastic/manifest.json`.
This is the one record `doctor`'s `version_match` and `check_manifest_sync` read, and the
one record `update` reads to decide which harnesses are installed and which are stale, so
no adapter can be silently skipped by a Claude-only default.

| Adapter | Version-truth path | Agent dir (`config[:dir]`) |
|---|---|---|
| Claude Code | `~/.claude/plastic/VERSION` | `~/.claude` |
| Codex CLI | `~/.agents/plastic/VERSION` | `~/.agents` |
| Hermes | `~/.hermes/plastic/VERSION` | `~/.hermes` |

## Capability tiers

An adapter declares the strongest tier it can honestly support. The tiers are about the
record: whether what the agent did reaches the ledgers.

- **Tier A (full record).** All three layers load, and L3 is complete: every write inside an
  intent directory reaches the savepoint ledger, every project write promotes its day-ledger
  line, child and parent agents are distinguished, and the lock heartbeat cannot be silently
  skipped.
- **Tier B (record-with-caveat).** All three layers load and shape decisions, but at least one
  L3 edge has a structural caveat (for example, a write path the record hook does not observe,
  or an envelope it cannot parse). The record lands, with a documented asterisk.
- **Tier C (conventions reliable, record best-effort).** L1 conventions load reliably and
  shape decisions, but L2 and L3 for spawned child agents are best-effort: live state and the
  record hook may not reach every child, so the ledgers cannot be relied upon for them.

## Per-agent layer x mechanism table

Each adapter fills this shape with the concrete mechanism it uses at each layer.
Empty here; adapters populate their own copy.

| Layer | Load mechanism | Honor mechanism |
|---|---|---|
| L1 standing conventions | | |
| L2 live state | | |
| L3 the record | | |

## Worked example: Claude Code (interactive only)

This example covers Claude Code used INTERACTIVELY. The `--bare`, headless, and CI
runs are explicitly out of scope (see the scope note below).

### L1 standing conventions

`CLAUDE.md` and `PLASTIC.md` inject into the top-level agent and into general-purpose and
custom sub-agents, so the standing conventions arrive without any per-call wiring. Exception:
the built-in Explore and Plan sub-agents skip `CLAUDE.md`, so they do not receive the
conventions. Do not route Plastic-bound work to Explore or Plan; they will act without the
standing rules.

### L2 live state

`SessionStart` (`hooks/session-start` -> `scripts/hook-session-start`) injects `PLASTIC.md`,
opens or joins today's day ledger under `~/.plastic/store/.sessions/<YYYYMMDD>/`, and writes
the per-session pointer (`.tmp/<session-id>/current`) and heartbeat. `UserPromptSubmit`
(`hooks/capture`) appends the prompt as a pending day-ledger line, detects `auto` and
`continue`, and hints at matching parked intents. `PreCompact` (`hooks/savepoint` ->
`scripts/hook-savepoint`) writes the session's hand-off into the day ledger
(`.sessions/<day>/handoff--<session>.md`) and prints one message naming that file; `SessionEnd`
(`hooks/close`) writes it once more, then closes the session. The same hand-off is written
at every ticked day-ledger item, and the session-start hook injects the day summary after the
joined line.

`SessionStart` is a top-level-only event: it fires for the main session, not for sub-agents.
Sub-agents fire `SubagentStart`, which Plastic does not use. So the session event alone cannot
carry live state into a spawned agent. The authoritative live-state mechanism for spawned
agents is the spawn preamble, `scripts/spawn-preamble <intent_dir> [--role ROLE] [--step STEP]`:
a deterministic block built purely from the intent directory on disk (no network, no
randomness, no clock read), reporting the active intent id and intent line, the current stage
(the last non-empty line of `savepoint.md` when present, else the stage derived from which
lifecycle files exist), the cycle role or step, the verbatim honoring instruction, and the
verbatim report contract (intent 74). The auto team lead prepends this preamble to every
dispatched agent's prompt.

### L3 the record

One `PostToolUse` hook, `record` (`hooks/record` -> `scripts/hook-record`), on the full write
matcher (Write, Edit, NotebookEdit, and the six Serena edit tools). It keys off the stdin
`session_id`, appends the intent-dir savepoint line from the written path alone, refreshes the
delivery-lock lease for the owning session (`Lock.heartbeat` refuses any other session), and
promotes the day-ledger line when a project file lands. It never blocks and always exits 0.
Intent-file content is validated at create time by `new-intent` and at close time by
`end-intent`'s structure check; doctor checks report on the record (intent 308).

### Tier

Claude Code interactive is **Tier B (record-with-caveat)**. All three layers load and shape
decisions. The caveat is at L3: the record hook's matcher is `Write|Edit|NotebookEdit` plus the
six Serena edit tools and does not include `Bash`, so a write made through a shell one-liner
into an intent directory never reaches the ledger and never refreshes the lock lease (the shell
matcher that once covered that path left with the gates in 2.0, intent 302). A second, L2 note:
a spawned agent receives live state only through the spawn preamble, never through the
session event, so a dispatch that skips the preamble boots an agent with no live state.

### Scope note

This worked example is interactive only. The `--bare`, headless, and CI execution paths are
explicitly OUT of scope here: the session id may be unset in those runs, so the session-keyed
record hook falls back to the derived key. Those paths get their own treatment elsewhere.

## Worked example: Codex CLI

Codex CLI is **Tier B (record-with-caveat)**, down from the Tier A it held while its
`PreToolUse` hooks could refuse a write before it landed (that mechanism was removed in 2.0,
intent 302, so no harness can claim it). The `PostToolUse` record hook observes `apply_patch`,
Codex's sole file-mutation tool, so every file operation reaches the record; the caveat is
that the hook fails open on any envelope its parser cannot read (the grammar is
primary-sourced as of intent 239, `test/fixtures/codex-v4a-grammar.txt`), so an operation the
parser does not understand leaves no ledger line. Two configuration disciplines apply:
register hooks and skills at USER scope so they survive Plastic's per-intent worktree, and
clear headless hook trust (managed hooks or `--dangerously-bypass-hook-trust`), since an
untrusted hook is silently skipped.

### L1 standing conventions

The installer's first-install presence probe tests `~/.codex` (Codex's own home,
`config[:home_dir]`), not `~/.agents` (`config[:dir]`, the shared cross-tool skills root any
AgentSkills-compliant tool can already have created). `~/.agents` itself is created by the
install when it does not yet exist (`install_skills_flat` and `generate_codex_agents` both
`mkdir_p` their own nested paths), so a machine with Codex installed but no other
AgentSkills-compliant tool no longer aborts on a missing directory it never owned (intent 198).

Skills copy flat and unmodified to `~/.agents/skills/plastic-<name>/` (copy-not-transform,
settled by 23 and reconfirmed by 181). Plastic's standing conventions inject into
`~/.codex/AGENTS.md` as a marked section: a small curated body (work flows through intents,
`~/.plastic/PLASTIC.md` is the source of truth and is never edited, skills are the operational
procedures, intent artifacts live under `~/.plastic/`), wrapped in
`<!-- BEGIN PLASTIC INTEGRATION hash:... -->` and `<!-- END PLASTIC INTEGRATION -->` markers.
The injector is three-state (create the file, append the section, or replace it in place) and
idempotent: re-injecting the same body reproduces the file byte for byte. Uninstall strips
exactly that section through a dedicated surgical pair, mirroring Claude Code's
`settings.json` hooks strip, so any content the user added elsewhere in `AGENTS.md` survives
both install and uninstall untouched. `doctor` verifies the section is present and well formed
(matched BEGIN and END markers) alongside the existing skills and agents checks.

### L2 live state (intent 199)

`SessionStart` fires `session-start` and `check-update`; `UserPromptSubmit` fires `capture`;
`PreCompact` fires `savepoint`. Each hook name is projected straight off the single
`HookRegistry.events` source (108 D7), the same total-projection shape as the record hook: a
hook added to any of these three events on the Claude side lands in Codex's `hooks.json`
automatically. `SessionEnd` fires `close` on Codex too (intent 309), projected from its own
constant, `HookRegistry::CODEX_SESSION_END_HOOKS`, never as a fourth live-state event, because
its dispatch differs: Codex kills a `SessionEnd` hook after 3 seconds (`SESSION_END_MAX_TIMEOUT_SEC`
in codex-rs), so `scripts/codex-hook` hands `close` to `hooks/close` in a detached child (own
process group, stdin from a pipe, output to `/dev/null`) and returns at once; the close hook's
own detached day filer does the slow part. Codex's current stable release ships both `Stop`
and `SessionEnd` (sourced against the codex-rs/hooks crate at rust-v0.149.1 and the official
hook docs); 296's cut inventory said it had neither, and that claim is superseded. The design
uses `SessionEnd` on both harnesses, since `Stop` fires per turn. One thing does not follow
automatically. `scripts/codex-hook` carries its own `STATE_HOOKS` literal (the four live-state
names plus `close`), which decides which names the dispatcher will actually relay, so a hook
added to or renamed in any of these events must be added there by hand. A cross-check in
`test/hook_registry_test.rb` fails when the two disagree (intent 246). The per-prompt
`power-tools` reminder was removed in 2.0 (intent 309); its name stays in
`RETIRED_HOOK_NAMES` so old registrations purge on update.

The stdin shape for these events differs from `apply_patch`'s diff envelope: no `tool_input`
at all, since none of them is a tool call. `scripts/codex-hook` reuses the exact launcher files
Claude already runs (`hooks/session-start`, `hooks/check-update`, `hooks/capture`,
`hooks/savepoint`, and `hooks/close` through the detached hand-off) unmodified: each is already harness-agnostic, since it
resolves `~/.plastic` off `$HOME` on its own and reads only the common stdin fields
(`user_prompt` for the `UserPromptSubmit` hook) the official Codex hooks doc confirms match
Claude's schema for these events. The dispatcher's only adaptation is threading the payload's
`session_id` into `CLAUDE_CODE_SESSION_ID` (Codex's own process env never carries it) and
bounding the call with a timeout (intent 289 fixed the leaking background call at the root;
the bound stays because Codex invokes hooks synchronously), then relaying stdout, stderr, and
exit code unchanged. `SubagentStart` is still not wired: no Plastic hook exists for it on any
harness today.

### Per-agent model mapping (intent 102a)

Each Plastic role file in `agents/*.md` installs on Codex as a whole-file, Plastic-owned,
manifest-tracked `~/.codex/agents/<name>.toml`, generated at install time. `name` and
`description` come from the source file's frontmatter; `developer_instructions` is the
Markdown body verbatim, escaped for a TOML multi-line basic string (backslash and quote
escaping so no `"""` delimiter collision can form, CRLF normalized to LF, C0 controls
escaped). Output is deterministic and byte-identical on regenerate.

The shipped model alias (`opus`, `sonnet`, `haiku`) resolves to BOTH a `model` line and a
`model_reasoning_effort` line, model first (intent 186, `AgentModels::CODEX_MODEL_BY_ALIAS`
paired with `AgentModels::EFFORT_BY_ALIAS`): opus roles to `gpt-5.6-sol` at `high`, sonnet
roles to `gpt-5.6-terra` at `medium`, haiku roles to `gpt-5.6-luna` at `low`. Codex has no
vendor alias layer of its own, so a Codex model id rots on every release; Plastic resolves that
by owning the alias itself, centralizing every id in one map. An existing
`agents.models.<name>` config override is honored by shape: an alias word maps to model and
effort together exactly like the default; any other value is written verbatim as a literal
`model` id only, with no effort line (the user owns that value and its staleness). An empty
value emits nothing, so an agent with no override and no shipped alias cleanly inherits the
user's globally configured Codex model. `doctor`'s codex check validates the generated `.toml`
files (presence plus a structural check for the mandatory fields).

`doctor`'s model-drift check (`check_agent_model_drift`) has a Codex-specific path since
intent 198, widened at intent 216: it reads `~/.codex/agents/plastic-*.toml` directly (plain
string matching, no TOML parser dependency) and reads the `model` and `model_reasoning_effort`
lines as two separate values, through independent regexes, so the model line is always opened
rather than skipped by a fallback. It compares the model value against the tier's resolved
Codex model id and the effort value against the tier's resolved effort, each comparison
skipped when its expected value is absent, so an alias with no mapped Codex model id never
reads as drift; detail lines name which field drifted. An `agents.models.codex.<name>`
override stays sanctioned and is never compared, because model and effort are user
configuration per harness and per project. The check validates only, it never enforces and it
never fails the boot.

The two advisor agents (`plastic-advisor`, `plastic-faux-advisor`) have a Codex pairing
defined at intent 186 (`plastic-advisor` to `gpt-5.6-sol` at `xhigh`, `plastic-faux-advisor`
to `gpt-5.6-terra` at `high`) but emission stays deferred: `generate_codex_agents` still
skips both `AgentModels::CONSULTATION_AGENTS` files by name, so no Codex TOML is written for
either yet.

### L3 the record (intent 102, cut to the record hook in intent 302)

`HookRegistry.codex_hooks_json` emits no `PreToolUse` group. The `PostToolUse` `record` hook
on the `apply_patch` matcher is the whole of L3: `scripts/codex-hook record` reads the Codex
stdin once, parses the apply_patch envelope once (`scripts/lib/apply_patch_envelope.rb`,
fail-open on a missing or unparseable envelope), and synthesizes one Claude-shaped
`PostToolUse` payload per file operation for `scripts/hook-record`, so the savepoint ledger,
the lock heartbeat, and the day ledger land the same way on both harnesses. A stale hook entry
from an older `~/.codex/hooks.json` falls through the dispatcher's fail-open `else` (exit 0,
no output) until the installer purges it (`HookRegistry::RETIRED_HOOK_NAMES`). Doctor's
`codex_hooks_implemented` check still diffs the dispatcher's `STATE_HOOKS` literal and `case`
labels against the registry in both directions, so a registered hook with no dispatcher
branch, or a branch nobody registers, is reported.

### config.toml (deferred, read-only advisory)

Plastic does not write `~/.codex/config.toml`, and has no TOML writer: the deferred settings
(`[features] hooks = true`, `sandbox_mode = "workspace-write"` with `writable_roots`,
`approval_policy`) stay owner-managed. Codex additionally loads an inline `config.toml
[hooks]` table as an equivalent to `hooks.json` (hook sources are additive, so either or both
may be present); Plastic documents this as the alternative it does not write to. `doctor` runs
a READ-ONLY scan of `config.toml` and warns when `[features] hooks = false` (or the deprecated
`codex_hooks = false` alias) or `sandbox_mode = "read-only"` is present, since either would
silently stop Plastic's hooks from firing; it never writes the file.

### Headless hook trust

Codex reviews hook trust by hash, at user scope too, and re-reviews on any change to the
hook's command. Interactive sessions trust the installed hooks via `/hooks`. Headless runs
(`codex exec`) need either `--dangerously-bypass-hook-trust` or a managed `requirements.toml`
shipped ahead of time; Plastic documents both paths and ships no trust artifact of its own.

Since intent 198, the installer itself prints the `/hooks` step after a successful Codex
install (`scripts/install.rb`'s `print_results`), so a user is told to trust the hooks instead
of discovering silently that no hook ever fires. `doctor`'s `check_codex_registration` adds a
`codex_hooks_trust` advisory (`warn`, never `pass` or `fail`) once hooks are registered as
expected: whether Codex persists a queryable trust record anywhere under `~/.codex` is
undocumented and unverified, so this can never be a real pass or fail check, only a reminder.
Because trust is keyed to each hook's current command hash, any future Plastic release that
changes a hook's command re-arms the review, and the advisory's wording says so.

### Minimum Codex version

The hooks feature and the headless trust-bypass fix land on the 0.13x release line onward
(verified on 0.144.x). User-scope registration (not the project-local `.codex/hooks.json`)
is required regardless of version, because the project-scoped file has an open
worktree-scoping bug.

## Roadmap

Later adapters extend this contract to other harnesses. They arrive as new ROOT intents (not
children of this one) with `sources: ["4a1c1", "7"]`, where intent 7 is the harness-adapters
umbrella and 4a1c1 is this foundation. Codex's L1 core (skills copy plus AGENTS.md
standing-conventions injection, intent 33a), L3 hooks (`hooks.json` registration, the
`apply_patch` envelope parser, the dispatcher, intent 102), and per-agent model mapping
(`~/.codex/agents/*.toml` generation, intent 102a) have all landed. Intent 198 closed the gap
between "shipped" and "actually works on a first install"; intent 199 closed Codex's L2
live-state gap; intent 302 removed the edit-path and stage-transition enforcement on both
harnesses, leaving the record hook; intent 309 aligned the five-event map on both harnesses,
wired Codex's `SessionEnd`, and retired the per-prompt power-tools reminder. Kimi Code and
Hermes adapters are carried by intents 102, 102a, and 73d, informed by 296's
`research--cross-harness-teams.md`; the line of sight after them is OpenClaw. All of them
target reasoning agents only.

## ScreenPaint: the paint seam (intent 317a)

`scripts/lib/screen_paint.rb` is the harness-agnostic paint seam 317's
follow-up named: a parser and re-layouter that turns any emitted plain screen
(intent, state, roster, delivered, delay) into the ANSI layout, reusing
IntentScreenAnsi's palette and fit helpers. The MessageDisplay adapter paints
the printed text through it (no intent-id resolution; grammar decides), and
`report-screen --ansi` delegates to it under the capability guards (TTY or
`PLASTIC_FORCE_COLOR=1`, `NO_COLOR` wins). `IntentScreenAnsi.render` remains
the record-driven renderer behind `intent-screen --ansi`. A screen the painter
cannot parse falls open: the CLI prints the plain text, the hook returns the
buffered original when chunks were already blanked and no envelope at all when
nothing engaged.

Engagement is late-capable (intent 331a): a chunk carrying a screen opener
engages the message from that chunk on, whatever its index, not only chunk 0.
A prose-first or fenced reply — the model talks before printing the screen,
or wraps it in a code fence — used to leave chunk 0's fast decision final and
the whole message unpainted; now chunk 0 still decides fast (no opener means
NOSCREEN, as before), but NOSCREEN is no longer final, and a later opener
replaces it. The engaging chunk's own prefix (the prose before the opener,
inside that same chunk) is returned as displayContent; everything from the
opener onward is buffered at that chunk's own index, which the shared decision
file now records so the final chunk — routinely a separate process — knows
where to start waiting and splicing, instead of burning its whole budget on
chunks that were never buffered at all. A lone fence wrapping the opener (one
line immediately before it, one immediately after the painted region) is
dropped; a fence in an earlier, already-displayed chunk is never touched, and
an opener split across two chunks' own deltas, with neither half matching
alone, still falls back to plain — a known, accepted limitation.
