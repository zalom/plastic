# Tiers and Dispatch

This chapter holds tier depth beyond the S/M/L definition, the agent-model and dispatch mechanics, and the auto-mode human reporting contract.

Speed comes from two levers only: artifact content depth and agent topology. The
same-structure invariant holds: same file set, stage order, gates, and savepoint ledger at
every tier and in both modes.

S/M collapse the topology (one thinker agent writes spec.md then plan.md plus
checklist.md plus at least one real action file in one context, consolidated into a single
actions/ACTION_1.md at S/M and one file per task at L; a sonnet executor implements). L
keeps the full team.

Never cut at any tier: the independent reviewer, outcome.md as truth of delivery, the
delivery lock, worktree isolation, intent creation via skill, INDEX as status truth, the
QMD reindex at End.

Guided mode is unchanged: full-depth artifacts, the human at every gate.

Every lifecycle stage has exactly one dispatchable background agent, plus the enforcer that
orchestrates them: see PLASTIC.md's Agent Models and Dispatch table for the stage-to-agent
mapping (What, Why, How, Exec, Done).

Final-gate code review stays an ad-hoc subagent the enforcer dispatches at the final gate, not
a standing role.

**The advisor: two consultation agents, never injected (intent 185).** Neither is a stage
role: never in PLASTIC.md's Agent Models and Dispatch table, never dispatched by the auto
pipeline, and neither ever touches a user's own session. `plastic-advisor` is the real advisor, ships `model: fable`,
expensive, billed through usage credits. `plastic-faux-advisor` is the imitation advisor, ships
`model: opus`, an ordinary model carrying the Operating Manual's reasoning discipline inlined
in its own body (not injected into anything), so it reasons the same disciplined way at a
fraction of the cost. The `plastic-agent-advisor` skill is the one front door: it teaches when
consulting is worth the money (from the Advisor Protocol: buy one-way doors, plans, adversarial
review, deadlocks, ranking; never buy what a tool can answer, code volume, or confirmation of a
decision already made), routes to the configured agent, and can set the config on request. The
user or the main session states a TIER (S, M, or L) and an EFFORT line in the brief; shipped
effort is `xhigh` for `plastic-advisor` and `max` for `plastic-faux-advisor`.

Config is harness-scoped, keys matching `InstallerCore::DEFAULT_AGENTS` exactly (`claude`,
`codex`, `hermes`, never `claude_code`): `advisor.enabled` (false skips installing both agents and the
skill), `advisor.claude.default` (which agent the skill routes to; an agent NAME never a model
name, so it can point at a locally registered agent, and the only advisor routing key the
installer writes). Each agent's actual model is a plain `agents.models.claude.<name>`
override, the SAME harness-scoped mechanism every other agent uses, resolved through
`InstallerCore#agent_model_overrides(harness:)`; there is no separate advisor-model key.
`agents.models` is harness-scoped from this release (`agents.models.claude.*`,
`agents.models.codex.*`), with the pre-existing flat form (`agents.models.<name>: value`)
still honored as the claude harness and nested winning over flat. This closes a real latent
bug: previously the same override map fed both the Claude frontmatter rewrite and the Codex
TOML generator, so a literal Claude model id could leak into a Codex config; a model named
under `claude` is now never emitted to `codex`. Install asks which advisor is the default
(Claude Code only), with a plain description of each: Faux Fable (recommended, cheaper,
available on any plan) or Fable 5 (the frontier model, billed through credits). Update asks
the same question once when the key is unset, then never again. Claude-only for this release:
the owner has not evaluated the Codex reasoning-model ecosystem long enough to judge it, so
`generate_codex_agents` skips both agents by name, tracked at intent 186, not a permanent
exclusion.

**Auto-mode entry.** `plastic-auto` is the entry skill for autonomous delivery: it takes over How
and Exec, spins up the stage-agent team named in PLASTIC.md's Agent Models and Dispatch table,
and works the dashboard's dispatchable queue. The dashboard's
`--data` output splits intents into a `dispatchable_queue` (work an agent can pick up) and
`human_only` (intents that need a person); auto mode consumes the former.

**Model contract.** Every agent in `agents/*.md` pins an explicit Claude Code model alias in
its own frontmatter: `opus`, `sonnet`, or `haiku`. Never `inherit`, never Fable by default,
unless an explicit `agents.models.<name>` config override names Fable for that role, in which
case the override is honored as written. The two advisors, `plastic-advisor` and
`plastic-faux-advisor`, are not lifecycle stage roles: the never-Fable rule governs stage
agents only. Neither is ever dispatched by the auto pipeline; they are consultation roles
summoned deliberately by the user or the main session, and their models are user configuration
(fable and opus by default on Claude Code). Aliases track "latest
per tier" so no Plastic release is required to advance a tier. The tier by role:
`plastic-enforcer`, `plastic-brainstorming`, `plastic-planner` are `opus`;
`plastic-spec-specialist`, `plastic-executor`, `plastic-intent-curator`,
`plastic-future-intent-researcher`, `plastic-intent-discovery` are `sonnet`.

**Config and installer mechanism.** `agents.models.<basename>` in a project's
`<dir>/.plastic_store/config.yml` or the global `~/.plastic/config.yml` overrides one agent's
tier. Precedence is project, then global, then the shipped default, matching every other
`read-config` key. The installer applies the resolved override to each agent file's `model:`
line at copy time (install, update, and repair, across every harness target). With no override
configured, the shipped frontmatter passes through unchanged.

**Dispatch-time contract.** Frontmatter is primary, and Claude Code reads it at dispatch, but
because that read is a harness implementation detail rather than a contract Plastic controls,
every dispatch site also resolves the target agent's model through the config chain
(`read-config agents.models.<basename> --project <repo>`) and passes it explicitly at dispatch,
belt-and-braces on top of the frontmatter pin.

**Cross-harness portability.** The dispatch and model-tier contract above is harness-facing. The
adapter layer that maps Plastic's hooks and model aliases onto each supported agent runtime
(Claude, Codex, Hermes) is the cross-harness portability layer; see
docs/reference/harness-adapters.md for the adapter contract.

**Spawn preamble (intent 152).** `scripts/spawn-preamble` emits a live-state block purely from
filesystem state: the active intent, stage, role/cycle-step, the honor instruction, and the
report contract. When the intent's code worktree is resolvable and exists on disk, it also
appends the worktree's absolute path plus a verbatim instruction to `cd` there directly, for
harnesses whose `EnterWorktree` cannot discover a nested repo from a non-repo launch directory.
Output is byte-identical when no worktree resolves.

**Orchestrator advisory.** At auto-mode start, the orchestrator recommends once that the user
run the main session on the best available thinking model (Fable, Opus, or whatever supersedes
them). This is advisory only: it changes no behavior and blocks nothing if ignored, and it
concerns the human's main session, never a dispatched subagent. The two advisors,
`plastic-advisor` and `plastic-faux-advisor`, are not lifecycle stage roles: the never-Fable
rule governs stage agents only. Neither is ever dispatched by the auto pipeline; they are
consultation roles summoned deliberately by the user or the main session, and their models are
user configuration (fable and opus by default on Claude Code).

**`plastic-intent-discovery`.** The What-stage agent. It fires at intent activation, after the
delivery lock is armed and before Why begins, running under that lock as the owner session (it
does not acquire the lock itself and is not blocked by it): it reads the intent's
`chain`/`sources` frontmatter, runs QMD-first discovery over completed predecessor work and
related parked or future intents, and deposits findings to `resources/discovery--<slug>.md` in
the intent directory ONLY. It never writes the intent file, `spec.md`, or any other lifecycle
deliverable; the Why-stage `plastic-brainstorming` agent reads its deposit and enriches
`## Context`.

`savepoint.md`: a deterministic, append-only ledger of cycle-step milestones (one line per
lifecycle boundary, newest at the bottom), written automatically by the gate hook. It is
sugar on top of the conventions, not a source of truth: state is always derivable from
files-on-disk, and the ledger is rebuildable. It exists so a resuming agent reads the cycle's
succession at a glance (last line = where we are).

### Auto-Mode Human Reporting (intent 92)

In auto mode the orchestrator briefs the human at every lifecycle stage boundary in a fixed,
impact-first shape (the EM-to-CTO report contract): State, then Risk, then Call. This is the
depth at M and L; at S the briefing fires once, at How. It leads with
what changed and why it matters, names one risk, and leaves the decision to the human. Separately,
the `plastic-humanizer` skill cleans authored prose (specs, outcomes, READMEs, release notes) of
AI tells and slop; it is for documents, not for every reply.
