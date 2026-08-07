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

### Lock provenance contract

Every adapter passes lock provenance explicitly when it knows it. `harness` uses the
adapter's canonical value, such as `claude`, `codex`, or `hermes`; `agent`, `model`, and
`thread` use the harness's actual values. Unknown harness, role, model, or thread values stay
`Unknown`. Adapters must not infer them from transcript paths, session-id formats, process
names, or model defaults.

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
this table cite; the gate scripts do not read `DEFAULT_AGENTS` at runtime (see the L1 dependency
note in the Codex worked example below), so the two are independently maintained by hand.

| Adapter | Invocation |
|---|---|
| Claude Code | `/plastic-<name>` (slash) |
| Codex CLI | `$plastic-<name>` (dollar), explicit; Codex may also select a skill implicitly by matching its `description` |
| Hermes | not yet defined (future adapter, see Roadmap below) |

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

Codex and Hermes previously wrote a flat `<agent-dir>/plastic-manifest.json` with no
per-agent `VERSION` file at all, so `update` could only ever act on Claude by default. A
one-time migration on next install unions the old flat manifest's files into the prune
set, then removes it; the version-truth path above is what every adapter converges on.

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

The create gate (PreToolUse, matcher Write, intent 60b) is the defense-in-depth complement
on the create path. On Claude it is one of five checks the merged `hooks/edit-gates` ->
`scripts/hook-edit-gates` dispatcher runs in-process (intent 244); `scripts/hook-create-gate`
remains the CLI wrapper Codex calls and the 45 hook contract tests still drive directly. When
the target path is an intent file inside its own equally-named dir
(`store/**/<id>--<slug>/<id>--<slug>.md`), it validates the PROPOSED content from the hook
stdin payload (`tool_input.content`) before the write lands, using `IntentValidator` for
born-complete frontmatter plus the sanctioned `##` section set, and blocks with exit 2 on
failure. It depends only on the stdin path plus content, never on the session bridge or any
session id, so it enforces even in headless and background runs. It is Claude-Code-only
defense-in-depth: the `new-intent` CLI plus the creating-intent instruction are the portable
lever that works on any harness (intent 60b D9). The PreToolUse block makes the PostToolUse
backstop a no-op for the create case, so the two never double-report.

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

## Worked example: Codex CLI

Codex CLI is rated **Tier A (full parity)**: `PreToolUse` hooks gate `apply_patch`, giving
a true pre-write veto for both create-path and in-place edits. This is the one axis
where Codex sits above Claude Code interactive, whose in-place-edit enforcement stays a
post-write backstop (see Tier B above). The verdict carries two caveats, both config
discipline rather than tier ceilings: register hooks and skills at USER scope so they
survive Plastic's per-intent worktree, and clear headless hook-trust (managed hooks or
`--dangerously-bypass-hook-trust`), since an untrusted hook is silently skipped rather
than blocking.

### L1 standing conventions

The installer's first-install presence probe tests `~/.codex` (Codex's own home,
`config[:home_dir]`), not `~/.agents` (`config[:dir]`, the shared cross-tool skills root any
AgentSkills-compliant tool can already have created). `~/.agents` itself is created by the
install when it does not yet exist (`install_skills_flat` and `generate_codex_agents` both
`mkdir_p` their own nested paths), so a machine with Codex installed but no other
AgentSkills-compliant tool no longer aborts on a missing directory it never owned (intent 198
fixed a defect that made every fresh Codex-only install fail before this).

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

### L2 live state (intent 199)

`SessionStart` fires `session-start` and `check-update`; `UserPromptSubmit` fires
`continue`, `future-intent-check`, `auto-arm`, and `power-tools`; `PreCompact` fires
`savepoint`. Each hook name is projected straight off the single `HookRegistry.events`
source (108 D7), the same total-projection shape as the file-mutation gates above: a hook
added to any of these three events on the Claude side lands in Codex's `hooks.json`
automatically. One thing does not follow automatically. `scripts/codex-hook` carries its own
`STATE_HOOKS` literal, which decides which names the dispatcher will actually relay, so a hook
added to or renamed in any of these three events must be added there by hand. A cross-check in
`test/hook_registry_test.rb` fails when the two disagree (intent 246).

The stdin shape for these three events differs from `apply_patch`'s diff envelope: no
`tool_input` at all, since none of the three is a tool call. `scripts/codex-hook` reuses the
exact launcher files Claude already runs for these seven hooks (`hooks/session-start`,
`hooks/check-update`, `hooks/continue`, `hooks/future-intent-check`, `hooks/auto-arm`,
`hooks/power-tools`, `hooks/savepoint`) unmodified: each is already harness-agnostic, since it
resolves `~/.plastic` off `$HOME` on its own and reads only the common stdin fields
(`user_prompt` for the four `UserPromptSubmit` hooks) the official Codex hooks doc confirms
match Claude's schema for these events. The dispatcher's only adaptation is threading the
payload's `session_id` into `CLAUDE_CODE_SESSION_ID` (Codex's own process env never carries
it) and bounding the call with a timeout (`hooks/check-update` backgrounds a real network
call without redirecting its output, and Codex invokes hooks synchronously), then relaying
stdout, stderr, and exit code unchanged, the same "drive the body, relay its output" pattern
already used for the file-mutation gates. `SubagentStart` is still not wired: no Plastic
hook exists for it on any harness today.

The shell-tool write hole this once left open, `bash-gate` never reaching Codex's shell tool,
is now closed; see the Bash matcher subsection under L3 below.

### Per-agent model mapping (intent 102a)

Each Plastic role file in `agents/*.md` installs on Codex as a whole-file, Plastic-owned,
manifest-tracked `~/.codex/agents/<name>.toml`, generated at install time instead of the
prior dead `~/.agents/agents/*.md` copy (that root is the cross-tool skills standard, not
an agents root, and Codex's native subagent loader never read it). `name` and
`description` come from the source file's frontmatter; `developer_instructions` is the
Markdown body verbatim, escaped for a TOML multi-line basic string (backslash and quote
escaping so no `"""` delimiter collision can form, CRLF normalized to LF, C0 controls
escaped). Output is deterministic and byte-identical on regenerate.

The shipped tier alias (`opus`, `sonnet`, `haiku`) resolves to BOTH a `model` line and a
`model_reasoning_effort` line, model first (intent 186, `AgentModels::CODEX_MODEL_BY_ALIAS`
paired with the existing `AgentModels::EFFORT_BY_ALIAS`): opus roles to `gpt-5.6-sol` at
`high`, sonnet roles to `gpt-5.6-terra` at `medium`, haiku roles to `gpt-5.6-luna` at `low`.
Codex has no vendor alias layer of its own, so a Codex model id rots on every release
(Codex ships multiple releases per week); Plastic resolves that by owning the alias itself,
centralizing every id in one map, so a Codex deprecation costs a single line plus a Plastic
release rather than a per-role file edit. An existing `agents.models.<name>` config override
is honored by shape: a tier word maps to model and effort together exactly like the default;
any other value is written verbatim as a literal `model` id only, with no effort line (the
user owns that value and its staleness). An empty value emits nothing, so an agent with no
override and no shipped tier alias cleanly inherits the user's globally configured Codex
model. `doctor`'s codex check validates the generated `.toml` files (presence plus a
structural check for the mandatory fields) in place of the flat `.md` check, which no
longer applies to codex. Hermes and `~/.codex/config.toml` are untouched by this slice.

`doctor`'s model-drift check (`check_agent_model_drift`) has a Codex-specific path since
intent 198: it reads `~/.codex/agents/plastic-*.toml` directly (the same plain string
matching `codex_agents_toml_check` already uses, no TOML parser dependency) and compares
each file's `model_reasoning_effort` line against the tier default, honoring an `agents.models.codex.<name>` override. Previously
this check globbed a path Codex never writes and always passed silently without opening a
single Codex file, so a drifted override could never be caught.

The two advisor agents (`plastic-advisor`, `plastic-faux-advisor`) have a Codex pairing
defined at intent 186 (`plastic-advisor` to `gpt-5.6-sol` at `xhigh`, `plastic-faux-advisor`
to `gpt-5.6-terra` at `high`) but emission stays deferred: `generate_codex_agents` still
skips both `AgentModels::CONSULTATION_AGENTS` files by name, so no Codex TOML is written
for either yet.

### L3 lifecycle gates and savepoints (intent 102)

Registration writes `~/.codex/hooks.json` at USER scope (defeats the open worktree-scoped
hook bug), derived from the single `HookRegistry` source so the Codex registration can never
drift from Claude's independently of it. Every file-mutation gate (`code-gate`, `lock-gate`,
`savepoint-pre`, `create-gate`) and the `gate-check` savepoint backstop collapse onto ONE
matcher, `apply_patch`, because it is Codex's sole file-mutation tool (every Codex edit
reports `tool_name: "apply_patch"`; there is no `Edit`/`Write` tool to match). `hooks.json`
is a partial-ownership file exactly like `AGENTS.md`: merged on install (a pre-existing user
hook entry survives untouched) and surgically stripped on uninstall, never manifest-tracked.

This is where Claude and Codex diverge in shape (intent 244). Claude collapsed its five
edit-path gates into one registered hook (`hooks/edit-gates` -> `scripts/hook-edit-gates`,
one process per Write/Edit); Codex keeps registering all five separately, since its own
per-gate `codex-hook <gate>` dispatch is unaffected and out of that intent's scope. The two
harnesses' Codex-facing entry points are the same either way: `HookRegistry.codex_hooks_json`
still emits its five per-gate `codex-hook` commands byte-identical to before, deriving its
order from `HookRegistry::CODEX_PRE_HOOKS & GATE_TOOLS.keys` and each `statusMessage` from
`HookRegistry::GATE_STATUS`, now that the five gate names no longer appear in Claude's
collapsed `events["PreToolUse"]`.

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

`links-gate` (registered in `HookRegistry::CODEX_PRE_HOOKS` since intent 192, but with no
dispatcher branch until intent 198) is the write-time belt for the PLASTIC.md `## Links`
contract: it reuses the exact same `LinksGate.decision` Claude's `hook-links-gate` drives, so
both harnesses share one decision function and can never disagree by construction.
`before_content` is the real on-disk file; `after_content` is the Update op's `added_content`.
This is a disclosed, narrower judgment than Claude's version: `ApplyPatchEnvelope.parse` only
ever captures a diff's added lines, never its removed or context lines, so for an Update whose
diff is a partial hunk rather than a full-file rewrite, `after_content` may not be the complete
proposed file. This is the same class of disclosed limitation the envelope parser's header
comment and `create-gate`'s own Update/Delete/Move handling already carry (best effort, never a
hard crash); running the same best-effort compare on Update ops here is strictly more coverage
than the total fail-open that shipped in v1.4.0.

The `apply_patch` V4A envelope's inner grammar (the exact shape of `*** Add/Update/Delete
File:` sections, `*** Move to:`, and the `+`/`-`/context line prefixes) is not
primary-sourced in either the guide this slice was built against or 181's report; the
parser is built to the best-known public shape and fails open on anything else. This slice
ships no live-Codex verification (the owner has no Codex installed): hermetic fixtures
carry the full burden. The owner's first real validation is a fresh `plastic-install
--codex` followed by a `doctor` run; `doctor`'s `codex_hooks_registered` check confirms
`hooks.json` carries exactly what `HookRegistry.codex_hooks_json` defines, with a fix hint
pointing back at the installer on any drift.

`codex_hooks_registered` only proves that `hooks.json`'s content agrees with what
`HookRegistry` would emit; both sides of that comparison come from the registry, so a pass
proves the registry agrees with itself, not that a registered gate actually does anything.
That gap let `links-gate` ship registered and reported healthy for its whole life in v1.4.0
with no dispatcher branch (found by hand in intent 198), and let `bash-gate` ship with a
working dispatcher branch never registered on Codex (intent 203), in the opposite direction.
`codex_hooks_implemented` (intent 200) closes both directions at once: it reads
`scripts/codex-hook`'s `STATE_HOOKS`/`SHELL_HOOKS` constants and its top-level `case gate`
statement as plain text, never `require`d or executed (the dispatcher reads `$stdin` and calls
`exit` at the top level, so loading it as Ruby would hang on stdin or exit before doctor got an
answer), the same plain-text-over-parser choice `codex_agent_toml_well_formed?` already makes
for Codex's agent TOML files, and diffs the extracted names against `HookRegistry`'s Codex
names in both directions: a name the registry emits with no dispatcher branch (registered, not
implemented, the `links-gate` shape) and a dispatcher branch nobody registers (implemented, not
registered, the `bash-gate` shape, plus dead code as a free byproduct). The extraction is
line-shape dependent, not AST-safe, and disclosed as such: if a future edit reshapes the
dispatcher (combined `when "a", "b"` arms, a multi-line array, a Hash-dispatch rewrite) so the
extractor recognizes zero gate names, the check fails loudly by design rather than silently
reporting a clean pass, since a check that finds nothing and calls that healthy would be this
exact disease one level up. `scripts/codex-hook`'s runtime behavior is unchanged: it still
exits 0 on an unrecognized gate; the loud failure lives only in doctor.

### Shell-tool gate: Bash matcher (intent 203)

Codex's shell tool reports `tool_name: "Bash"`, confirmed against the official Codex hooks
doc, with the command in `tool_input.command`. One more hook Claude already wires on its
`Bash` matcher now reaches Codex the same way: `bash-gate`, which denies a shell write to
project code before the active intent reaches How, the same lifecycle discipline the
`apply_patch` gates above already enforce.

The Codex matcher is `Bash` alone: the official Codex hooks doc's PreToolUse event catalog
enumerates exactly `Bash`, `apply_patch`, and MCP tool calls, and neither it nor the two prior
Codex research passes (198's official-docs research, 181's deep research) documents a discrete
`Read`, `Grep`, or `Glob` tool name. Registering a tool name Codex never reports would be dead
weight that looks alive, so `HookRegistry::CODEX_BASH_HOOKS` intersects against the same `Bash`
matcher Claude already uses (see `HookRegistry.events`).

The dispatch is a third payload category in `scripts/codex-hook`, a peer to the file-mutation
`apply_patch` gates and the live-state hooks, not folded into either. A shell command carries
no `apply_patch` diff envelope, so routing it through `ApplyPatchEnvelope.parse` would yield an
empty op list and hit the dispatcher's own `exit 0 if ops.empty?` fail-open line, silently
reopening the exact hole this intent closes. Instead `bash-gate` execs the SAME
`scripts/hook-bash-gate` file Claude already runs, unmodified, relaying Codex's raw stdin,
exit code, and stderr, the identical "drive the body, relay its output" pattern intent 199
used for the live-state hooks. Because the gate body runs unchanged, the audited
`# plastic-ok` escape (logged to
`~/.plastic/.cache/gate-escapes.log`) works on Codex with no new code.

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

Since intent 198, the installer itself prints the `/hooks` step after a successful Codex
install (`scripts/install.rb`'s `print_results`), so a user is told to trust the hooks instead
of discovering silently that no gate ever fires. `doctor`'s `check_codex_registration` adds a
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

Later adapters extend this contract to other harnesses. They arrive as new ROOT
intents (not children of this one) with `sources: ["4a1c1", "7"]`, where intent 7 is
the harness-adapters umbrella and 4a1c1 is this foundation. Codex's L1 core (skills copy
plus AGENTS.md standing-conventions injection, intent 33a), L3 hooks and gates
(`hooks.json` registration, the `apply_patch` envelope parser, the dispatcher, intent 102),
and per-agent model mapping (`~/.codex/agents/*.toml` generation, intent 102a) have all
landed. Intent 198 closed the gap between "shipped" and "actually works on a first install":
the directory-presence probe, the missing links-gate dispatcher branch, the hook-trust
reminder, and the Codex model-drift check. Intent 199 closed Codex's L2 live-state gap:
`SessionStart`, `UserPromptSubmit`, and `PreCompact` now reach Codex the same way they reach
Claude. Intent 203 closed the shell-tool gate hole: `bash-gate` now reaches Codex's `Bash`
tool, matched on `Bash` alone since that is the one shell-tool name the official Codex hooks
doc confirms (no discrete `Read`, `Grep`, or `Glob` tool is documented). The
current line of sight for the remaining harnesses is Hermes, then OpenClaw. All of them target
reasoning agents only.
