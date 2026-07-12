# Harness Adapters

How a reasoning agent harness loads, honors, and enforces Plastic. This is the
contract every adapter fills in, the capability tiers an adapter can claim, and one
fully worked example (Claude Code, interactive).

## Purpose and use model

Plastic is for reasoning agents, in two shapes:

1. A user working directly inside a reasoning agent, using Plastic as the operating
   scaffold for their own thinking and delivery.
2. A user instructing a reasoning agent to use Plastic to deliver the user's intents,
   producing a human-legible system of intents, specs, plans, and outcomes.

Both shapes assume a reasoning agent on the other side. Plastic targets reasoning
agents only. It is not a library you call from ordinary application code, and it does
not target non-reasoning automation. A harness adapter is the glue that makes one
specific agent harness load Plastic's conventions, honor its decisions, and enforce
its gates.

## The contract

Plastic reaches an agent across three layers. An adapter is judged on how each layer
arrives and how strongly it is honored. "Honor" splits in two: decision-shaping makes
the agent CHOOSE to follow, hard-enforcement BLOCKS the agent when it does not (and
includes artifact validity).

| Layer | Load (does it arrive) | Honor: decision-shaping (agent chooses to follow) | Honor: hard-enforcement (block when it doesn't) |
|---|---|---|---|
| L1 standing conventions | Convention docs (PLASTIC.md, AGENTS.md, CLAUDE.md) auto-inject into the agent's context at start | The conventions frame every decision; the agent reads them as standing rules | None at this layer: conventions persuade, they do not block |
| L2 live state | The active intent's id, stage, and role arrive at the point of work (session event and/or spawn preamble) | The live snapshot tells the agent where it is in the cycle so it acts in-stage | None directly; feeds the L3 gates that do block |
| L3 lifecycle gates + savepoints | Gate and savepoint hooks fire on file writes within the intent dir | Gate context nudges the next correct lifecycle move | Stage gates block out-of-order writes; the artifact-validity backstop rejects an intent file that is not born complete; savepoints record each milestone |

## Capability tiers

An adapter declares the strongest tier it can honestly support.

- **Tier A (full parity).** All three layers load AND hard-enforcement is real at L3:
  out-of-order writes are blocked, artifact validity is enforced, child and parent
  agents are distinguished, and the gates cannot be silently bypassed.
- **Tier B (parity-with-caveat).** All three layers load and shape decisions, but at
  least one hard-enforcement edge has a structural caveat (for example, enforcement
  fires after the write rather than preventing it, so the block is a loud signal
  rather than a true veto). Conventions and live-state are reliable; gates work but
  carry a documented asterisk.
- **Tier C (conventions reliable, child gates best-effort).** L1 conventions load
  reliably and shape decisions, but L2/L3 for spawned child agents are best-effort:
  live state and gates may not reach every child, so child-agent enforcement cannot
  be relied upon.

## Per-agent layer x mechanism table

Each adapter fills this shape with the concrete mechanism it uses at each layer.
Empty here; adapters populate their own copy.

| Layer | Load mechanism | Decision-shaping mechanism | Hard-enforcement mechanism |
|---|---|---|---|
| L1 standing conventions | | | |
| L2 live state | | | |
| L3 lifecycle gates + savepoints | | | |

## Worked example: Claude Code (interactive only)

This example covers Claude Code used INTERACTIVELY. The `--bare`, headless, and CI
runs are explicitly out of scope (see the scope note below).

### L1 standing conventions

`CLAUDE.md` and `PLASTIC.md` auto-inject into the top-level agent and into
general-purpose and custom sub-agents, so the standing conventions arrive without any
per-call wiring. Exception: the built-in Explore and Plan sub-agents skip `CLAUDE.md`,
so they do not receive the conventions. Do not route Plastic-bound work to Explore or
Plan; they will act without the standing rules.

### L2 live state

`SessionStart` is a top-level-only event: it fires for the main session, not for
sub-agents. Sub-agents fire `SubagentStart`, which Plastic does not use. So the
session event alone cannot carry live state into a spawned agent. The authoritative
live-state mechanism for spawned agents is the spawn preamble, `scripts/spawn-preamble`
(built in intent 4a1c1).

`scripts/spawn-preamble <intent_dir> [--role ROLE] [--step STEP]` emits a deterministic
block built purely from the intent directory on disk: no network, no randomness, no
clock read, so two runs over the same state are byte-identical. It reports the active
intent id and intent line (read from the intent file frontmatter), the current stage
(the last non-empty line of `savepoint.md` when present, else the stage derived from
which lifecycle files exist), the cycle role or step (from `--role`/`--step`, else the
derived stage), the verbatim honoring instruction (the agent must emit valid
lifecycle artifacts, must not hallucinate intents or stages, and its primary output is
valid lifecycle artifacts which it closes with a structured report about), and the
verbatim report contract (intent 74: the agent must end with a structured completion
report as its final message). The auto-mode enforcer prepends this preamble to every
dispatched specialist's prompt, so each spawned agent boots with accurate live state.

### L3 lifecycle gates and savepoints

The gate and savepoint hooks key off the stdin `session_id`. The savepoint ledger is
decoupled from bridge resolution: it is derived from the written file's intent
directory before any bridge lookup, so a milestone is recorded even when no bridge or
session exists. The stage gates (Why needs the What complete, How needs `spec.md`, and
so on) block out-of-order writes.

`IntentValidator` is the artifact-validity backstop, run inside `hook-gate-check`
(built in intent 4a1c1). When the written file IS the intent file itself (the
`<id>--<slug>.md` directly inside `store/<id>--<slug>/`, NOT `spec.md`, `plan.md`,
`checklist.md`, `outcome.md`, or `savepoint.md`), the hook validates its frontmatter.
An invalid intent file produces a loud stderr warning that names the failing field(s)
and a non-zero exit. PostToolUse caveat: the hook runs AFTER the write, so it cannot
prevent the file from landing on disk. The non-zero exit is the rejection signal, not
a true veto. A valid intent file (or any non-intent lifecycle file) preserves the
existing behavior exactly: the savepoint is appended and the hook exits 0.

The create gate (`hook-create-gate`, PreToolUse, matcher Write, intent 60b) is the
defense-in-depth complement on the create path. When the target path is an intent file
inside its own equally-named dir (`store/**/<id>--<slug>/<id>--<slug>.md`), it validates
the PROPOSED content from the hook stdin payload (`tool_input.content`) before the write
lands, using `IntentValidator` for born-complete frontmatter plus the sanctioned `##`
section set, and blocks with exit 2 on failure. It depends only on the stdin path plus
content, never on the session bridge or any session id, so it enforces even in
headless and background runs. It is Claude-Code-only defense-in-depth: the `new-intent`
CLI plus the creating-intent instruction are the portable lever that works on any harness
(intent 60b D9). The PreToolUse block makes the PostToolUse backstop a no-op for the
create case, so the two never double-report.

Child versus parent agents are distinguished via `agent_id`.

### Tier

Claude Code interactive is **Tier B (parity-with-caveat)**. All three layers load and
shape decisions. For an intent-file create the PreToolUse create gate is a true veto
(it blocks before the write); for in-place edits the L3 artifact-validity enforcement
stays a PostToolUse backstop that fires after the write and signals loudly rather than
preventing it.

### Scope note

This worked example is interactive only. The `--bare`, headless, and CI execution
paths are explicitly OUT of scope here: the session id may be unset in those runs,
so the session-keyed gate falls back to the derived key, and the enforcer falls back to
manual gating. Those paths get their own treatment elsewhere.

## Worked example: Codex CLI (L1 + L3 core; L2 deferred)

Codex CLI is rated **Tier A (full parity)**: `PreToolUse` hooks gate `apply_patch`, giving
a true pre-write veto for both create-path and in-place edits. This is the one axis
where Codex sits above Claude Code interactive, whose in-place-edit enforcement stays a
post-write backstop (see Tier B above). The verdict carries two caveats, both config
discipline rather than tier ceilings: register hooks and skills at USER scope so they
survive Plastic's per-intent worktree, and clear headless hook-trust (managed hooks or
`--dangerously-bypass-hook-trust`), since an untrusted hook is silently skipped rather
than blocking.

### L1 standing conventions

Skills copy flat and unmodified to `~/.agents/skills/plastic-<name>/` (copy-not-transform,
settled by 23 and reconfirmed by 181). Plastic's standing conventions inject into
`~/.codex/AGENTS.md` as a marked section: a small curated body (work flows through
intents, `~/.plastic/PLASTIC.md` is the source of truth and is never edited, skills are
the operational procedures, intent artifacts live under `~/.plastic/`), wrapped in
`<!-- BEGIN PLASTIC INTEGRATION hash:... -->` and `<!-- END PLASTIC INTEGRATION -->`
markers. The injector is three-state (create the file, append the section, or replace it
in place) and idempotent: re-injecting the same body reproduces the file byte for byte.
Uninstall strips exactly that section through a dedicated surgical pair, mirroring
Claude Code's `settings.json` hooks strip, so any content the user added elsewhere in
`AGENTS.md` survives both install and uninstall untouched. `doctor` verifies the section
is present and well formed (matched BEGIN and END markers) alongside the existing
skills and agents checks.

### L2 live state (deferred)

`SessionStart`, `UserPromptSubmit`, and `SubagentStart` context injection for Codex are
future work, out of this slice. Per-agent model mapping (`[agents.<name>].model` and
`model_reasoning_effort`) is intent 102a's, also not this slice.

### L3 lifecycle gates and savepoints (intent 102)

Registration writes `~/.codex/hooks.json` at USER scope (defeats the open worktree-scoped
hook bug), derived from the single `HookRegistry.events` source so the Codex registration
can never drift from Claude's independently of it. Every file-mutation gate (`code-gate`,
`lock-gate`, `savepoint-pre`, `create-gate`) and the `gate-check` savepoint backstop
collapse onto ONE matcher, `apply_patch`, because it is Codex's sole file-mutation tool
(every Codex edit reports `tool_name: "apply_patch"`; there is no `Edit`/`Write` tool to
match). `hooks.json` is a partial-ownership file exactly like `AGENTS.md`: merged on
install (a pre-existing user hook entry survives untouched) and surgically stripped on
uninstall, never manifest-tracked.

The one real translation cost is the payload shape. Claude hands a hook a clean
`tool_input.file_path` plus `tool_input.content`; Codex hands a diff envelope in
`tool_input.command` (the `apply_patch` V4A patch text), and one `apply_patch` call can
bundle several file operations (Add, Update, Delete, Move/rename). `ApplyPatchEnvelope.parse`
is the one new translation piece: a pure parser that walks the `*** Begin Patch` /
`*** End Patch` envelope and returns an ordered list of `{op:, path:, added_content:}` for
every `*** Add/Update/Delete File:` section, folding a trailing `*** Move to:` into the
op's effective path. It fails open (returns an empty list and warns to stderr) on any
missing or unparseable envelope, so a gate can never hard-crash on a payload shape it does
not recognize.

One Ruby dispatcher, `scripts/codex-hook <gate>`, reads the Codex hook stdin once
(`session_id` at top level, the envelope in `tool_input.command`), parses it, and drives
the SAME payload-agnostic Ruby gate and savepoint cores Claude's bash shims already drive,
once per file operation, so none of the four reused cores change at all. Their output
contracts were already Codex-compatible verbatim (`permissionDecision:"deny"` for
`lock-gate`, exit 2 for `code-gate`/`create-gate`, `decision:"block"` for `gate-check`), so
the dispatcher relays stdout, stderr, and exit code unchanged. On a multi-file patch, a
PreToolUse veto denies the whole `apply_patch` call on the first violating file.
`create-gate` validates born-complete content inline for Add operations on intent files
only; Update, Delete, and Move operations defer to the PostToolUse `gate-check` backstop,
which re-validates the intent file after the write lands, so nothing goes unchecked.

The `apply_patch` V4A envelope's inner grammar (the exact shape of `*** Add/Update/Delete
File:` sections, `*** Move to:`, and the `+`/`-`/context line prefixes) is not
primary-sourced in either the guide this slice was built against or 181's report; the
parser is built to the best-known public shape and fails open on anything else. This slice
ships no live-Codex verification (the owner has no Codex installed): hermetic fixtures
carry the full burden. The owner's first real validation is a fresh `plastic-install
--codex` followed by a `doctor` run; `doctor`'s `codex_hooks_registered` check confirms
`hooks.json` carries exactly what `HookRegistry.codex_hooks_json` defines, with a fix hint
pointing back at the installer on any drift.

### config.toml (deferred, read-only advisory)

Plastic does not write `~/.codex/config.toml` this slice, and has no TOML writer: the
deferred settings (`[features] hooks = true`, `sandbox_mode = "workspace-write"` with
`writable_roots`, `approval_policy`) stay owner-managed. Codex additionally loads an
inline `config.toml [hooks]` table as an equivalent to `hooks.json` (hook sources are
additive, so either or both may be present); Plastic documents this as the alternative it
does not write to, not something it merges into. `doctor` runs a READ-ONLY scan of
`config.toml` and warns when `[features] hooks = false` (or the deprecated `codex_hooks =
false` alias) or `sandbox_mode = "read-only"` is present, since either would silently stop
Plastic's gates from firing; it never writes the file.

### Headless hook trust

Codex reviews hook trust by hash, at user scope too, and re-reviews on any change to the
hook's command. Interactive sessions trust the installed hooks via `/hooks`. Headless runs
(`codex exec`) need either `--dangerously-bypass-hook-trust` or a managed
`requirements.toml` shipped ahead of time; this slice documents both paths and ships no
trust artifact of its own.

### Minimum Codex version

The hooks feature and the headless trust-bypass fix land on the 0.13x release line onward
(verified on 0.144.x). User-scope registration (not the project-local `.codex/hooks.json`)
is required regardless of version, because the project-scoped file has an open
worktree-scoping bug.

## Roadmap

Later adapters extend this contract to other harnesses. They arrive as new ROOT
intents (not children of this one) with `sources: ["4a1c1", "7"]`, where intent 7 is
the harness-adapters umbrella and 4a1c1 is this foundation. Codex's L1 core (skills copy
plus AGENTS.md standing-conventions injection, intent 33a) and L3 hooks and gates
(`hooks.json` registration, the `apply_patch` envelope parser, the dispatcher, intent 102)
have both landed. Codex's L2 live-state injection and per-agent model mapping (102a)
remain future work. The current line of sight for the remaining harnesses is Hermes, then
OpenClaw. All of them target reasoning agents only.
