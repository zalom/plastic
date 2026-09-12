---
name: plastic-auto
description: >-
  Autonomous intent delivery - a background team takes a registered intent from How to End.
  Use when user says "auto", "take it from here", "deliver this", or when a thinking
  conversation concludes and the user confirms autonomous execution. Requires an active intent
  in INDEX.md.
user-invocable: true
---

# Auto - Autonomous Intent Delivery

Announce: "Taking over intent [ID] - [name] for autonomous delivery."

**Advisory (not a rule).** At auto-mode start, recommend once that the user run this
orchestrating session on the best available thinking model (Fable, Opus, or whatever supersedes
them); this is advice only, and dispatched agents keep their configured model, never resolving
to Fable without an explicit `agents.models.<name>` config override. `plastic-advisor` and
`plastic-faux-advisor` are consultation roles the user or this session summons deliberately;
the auto pipeline never dispatches them.

## Precondition

An active intent MUST exist in INDEX.md. If none exists, refuse: "No active intent found.
Create one first with /plastic-intent-creating."

If several active intents exist, ask which to deliver (the one question auto asks at boarding).

**Picking work when no intent is specified.** If the user says "auto" without naming an intent
and none is active, consult the roadmap first (the primary planning surface), then fall back to
the dashboard queue:

```bash
ruby ~/.plastic/scripts/roadmap-next --roadmaps-dir <tier>/roadmaps
```

Branch on `state`: `dispatchable` means work its `dispatchable_queue` in `rank` order (the
current batch's `queued` intents, parallel-safe within the batch); `in_flight` means the
frontier batch is still delivering, report it and wait, never dispatch a later batch; `none` or
`exhausted` means fall back to `ruby ~/.plastic/scripts/dashboard.rb all --json` and work its
`dispatchable_queue` in `rank` order, leaving `human_only` and `next_big_thing` for the user.

QMD-first (when available): when the user describes the work instead of naming an intent, run
`ruby ~/.plastic/scripts/qmd-sync search "<terms>"` first, then open the hit's authoritative intent file; a no-op when QMD is absent.

## Take the intent (do this FIRST)

Immediately after selecting the intent, take it for this session. One verb acquires the durable
`delivery.lock` in the intent directory (stamped `run_mode: auto`), provisions the code worktree
at `<repo>/.claude/worktrees/{id}--{slug}` on branch `plastic/{id}--{slug}`, and points this
session at the intent (`~/.plastic/store/.tmp/<session>/current`), so the record hook writes
savepoint lines and heartbeats for it instead of the day ledger:

```bash
codex="${CODEX_THREAD_ID:-}"; claude="${CLAUDE_CODE_SESSION_ID:-}"
ruby ~/.plastic/scripts/plastic-lock arm --intent-dir "<STORE>/<dir>" --mode auto \
  --agent plastic-enforcer \
  ${codex:+--harness codex --session "$codex" --thread "$codex"} \
  ${claude:+--harness claude --session "$claude"}
```

Replace `<STORE>` (`~/.plastic/projects/<slug>/store` or `~/.plastic/store`) and `<dir>` (the
`ID--slug` directory). The snippet trusts a nonblank `CODEX_THREAD_ID` as Codex, otherwise a
nonblank `CLAUDE_CODE_SESSION_ID` as Claude, otherwise passes no identity and the verb keys the
lock by a derived session key. Never guess identity from an absent runtime variable; an
unknown harness or thread stays unknown. Exit 1 means the lock is held, stale, excluded, or
corrupt - or `inline_refused`: a conversation session may not arm an intent at all (owner rule
2026-08-31); dispatch the delivery team instead. `--allow-inline` exists only for an explicit
owner override. Do not proceed as the owner after an exit 1.

Read `../plastic-conventions/references/locks-and-worktrees.md` for what the lock and the
worktree mean and the station table behind them. Code edits happen only inside the worktree.

## The shape

Work is a graph (`graph.md`: Goal, Decisions, Graph, Status; one `nodes/*.md` per node) or,
for work small enough to skip speccing, delivered inline with no separate plan review. There
is no intent tier and no stage agent; depth follows the work.

`runner step` computes readiness and prints a spawn block per dispatched node - agent, model,
packet path, the test command, the call cap - fenced for a session to paste into the Agent
tool; the runner never spawns (327 D42). `runner status` renders the ledger; `runner answer`
closes a `needs_decision` node.

A lead is a choice, not a requirement (D8, 355). A lead earns its keep on a graph carrying a
decision node, weighing its `needs_decision` stop; a graph with none runs end to end from
`runner step` alone. When this session leads, it is the `plastic-enforcer` role, never a
dispatched agent.

## Team

- **plastic-enforcer**: this session. Writes the Why and How record, dispatches, applies
  review findings, verifies, closes.
- **plastic-executor**: one dispatch per intent, implements the consolidated action tests first,
  ticks the checklist, appends `## Insights`, drives the suite green.
- **the plan reviewer**: an optional dispatch before code, from `plastic-intent-executing`'s
  `plan-reviewer-prompt.md`; a fresh agent, never the lead.
- **the post-execution reviewer**: dispatched only by the risk rule, from
  `code-quality-reviewer-prompt.md`; a fresh agent, never the maker.

Spawn preamble (live-state injection): before dispatching any agent, run
`scripts/spawn-preamble <intent_dir> --role <role>` and PREPEND its output to the prompt. The
preamble is a deterministic, filesystem-only snapshot of the intent (id, intent line, current
stage, the worktree path when it exists) plus the honoring instruction and the report contract.

Dispatch-time model contract: resolve each agent's model through the config chain
(`read-config agents.models.<basename> --project <repo>`: project override, then global, then
the shipped default) and pass it explicitly at dispatch; never rely on the role's frontmatter
alone.

Completion report (require, then synthesize): every dispatched agent MUST end with a structured
completion report as its final message (`references/agent-report-contract.md`). When an agent
returns no usable report, run `scripts/agent-report <intent_dir> --role <role>` to synthesize a
deterministic filesystem-derived one, so the handoff account always exists.

### Delegation (agents writing under the owner's lock)

This session owns the delivery lock. A dispatched agent runs in its own session, so register
each one as a delegate before (or when) it needs to write into the intent dir:

1. Instruct each spawned agent to report its session id and runtime identity in its first
   message: `CODEX_THREAD_ID` for Codex, or `CLAUDE_CODE_SESSION_ID` for Claude. Use the
   agent's own identity when known; never infer a harness or model from missing context.
2. As the lock owner, run:
   `ruby ~/.plastic/scripts/plastic-lock delegate --intent-dir <intent-dir> --delegate <specialist-session-id> --harness <specialist-harness-when-known> --agent <role> --model <resolved-model-when-known> --thread <reported-CODEX_THREAD_ID-when-Codex>`
   Omit `--harness`, `--model`, or `--thread` when that value is unknown; `--agent <role>` is
   always known from the roster.
3. Immediately after the specialist returns, and before validating or dispatching
   the next handoff, classify the return and record its activity status as the owner:
   - `finished` means the specialist returned a usable completion report, whether
     agent-authored or synthesized through `scripts/agent-report`.
   - `failed` means the specialist returned blocked, errored, or without a usable
     completion report that can be synthesized.
4. Record the classification with exactly one of:
   ```bash
   ruby ~/.plastic/scripts/plastic-lock delegate --intent-dir <intent-dir> \
     --delegate <specialist-session-id> --status finished --harness <same-specialist-harness-when-known> \
     --agent <same-role> --model <same-resolved-model-when-known> --thread <same-CODEX_THREAD_ID-when-Codex>
   ruby ~/.plastic/scripts/plastic-lock delegate --intent-dir <intent-dir> \
     --delegate <specialist-session-id> --status failed --harness <same-specialist-harness-when-known> \
     --agent <same-role> --model <same-resolved-model-when-known> --thread <same-CODEX_THREAD_ID-when-Codex>
   ```
   Apply the same omission rule to unknown values on terminal status commands. A failed agent
   stops that handoff under the error procedure; never dispatch the next agent first.

Only the owner can delegate. Delegates cannot re-delegate or release.

Headless note: in a headless or background run the session id may be unset; the arm verb then keys the lock by a derived key and the record hook still writes the ledger.
Verify with `plastic-lock status` rather than assuming.

Solo fallback: on a harness with no agent dispatch (Codex CLI today), this session walks the
graph (or the plan) itself, still writing the matrix and the tests first and reviewing its own
plan against the matrix before code, saying so in `## Insights`.

## Stage-Aware Entry

Read the active intent's `savepoint.md` FIRST: the last line classifies the stage, and you
verify only that line's artifact before entering. Fall back to the filesystem probe when the
ledger is missing (then rebuild it with `Savepoint.rebuild_savepoint`).

| Ledger last line | Enter |
|---|---|
| `What  {id}--{slug}.md` (born) or no spec | Why (write spec.md) |
| `Why  spec.md created` | How |
| `How  plan.md created` / `How  checklist.md created` / `Exec  started` | Exec (verify plan, matrix, checklist) |
| `Exec  outcome.md created` | Exec done; complete the intent |
| A terminal savepoint line (`delivered` or `abandoned`) | Terminal; do not resume |
| A node or `Intent` transition line (`n1  running ...`, `Intent  needs_decision ...`) | Exec; a graph delivery is in progress - drive it through `scripts/runner`'s three public verbs, `step` (one turn of the dispatch loop), `status` (renders ledger state, safe to poll constantly), and `answer` (closes a `needs_decision` node) - read node status through `NodeLedger.status` before dispatching anything, never re-derive it by eye. `scripts/graph-measure` is the read-only sibling over that same ledger, with its own three public verbs `intent`, `budget`, and `cohorts` - it never dispatches and never writes |

Filesystem fallback, in order: `checklist.md` with items checked means resume Exec from the
first unchecked item; `plan.md` plus `checklist.md` means enter Exec; `spec.md` alone means
enter How; `## Context` with content means complete Why; only `## Intent` means start Why.

Announce which stage you are entering and why.

## Why (the lead)

For a graph delivery, Why is already written into `graph.md`'s Goal and Decisions; nothing
else to do here. For work with no graph: read `## Context` and `### Decisions`, assess the
gaps, research them yourself (code, docs, related intents through `## Links`, the web if
needed; no questions to the human), record each decision in `## Context > ### Decisions` with
its rationale, log it in `## Insights` with the `(autonomous)` marker through
`scripts/insight-append`, and write `spec.md` only when the intent needs one (speccing is
optional). Then How.

## How (the lead), then the plan review

For a graph delivery, How is `graph.md` itself: no `plan.md`, no separate plan review (D1,
341). For work with no graph: write `plan.md` (numbered steps) and at least one real
`actions/ACTION_N.md` carrying the failure-mode matrix (one row per operation, the failure
mode, the test that catches it; a `.gitkeep`-only `actions/` is not a finished How), then
`checklist.md` covering every action. The plan reviewer is optional, not a required step:
when the delivery warrants review before code, dispatch it (boot 1) with
`plastic-intent-executing`'s `plan-reviewer-prompt.md`, the spawn preamble, and the intent
directory, apply every finding to the spec, the matrix, and the tests, and record what was
dropped and why in the action file's review notes. A REVISE verdict is applied and not
re-reviewed unless a finding changes a decision.

Print `ruby ~/.plastic/scripts/report-screen plan <intent_dir>` as the first characters of
the reply, nothing before it, no fence, before dispatching the executor (see
`references/human-report-contract.md` for the full binding table). It informs; it does not wait.

Then Exec.

## Exec (the executor)

For a graph delivery, `runner step` prints the spawn block for the next ready node; paste it
into the Agent tool, verbatim. For work with no graph, dispatch `plastic-executor` (boot 2)
through `plastic-intent-executing` with the whole consolidated action pasted in.

1. Read the executor's return by code: DONE or DONE_WITH_CONCERNS proceeds; NEEDS_CONTEXT
   re-dispatches with the missing context; BLOCKED stops under the error procedure.
2. Tick the checklist as items land (the executor does this); verify tick-versus-diff against
   the diff. A mismatch is a review finding, not a lead cleanup.

## Review by risk (boot 3, only when a rule fires)

Dispatch the post-execution reviewer with `code-quality-reviewer-prompt.md` when any of these
holds, each checkable from disk with no judgment; otherwise the green suite is the review:

1. `git diff --name-only <red-commit>..HEAD` touches a path on the risk list in
   `references/agent-architecture.md` (hooks, the lock, the arming module, the installer, a
   release file).
2. A row of any failure-mode matrix (an `actions/ACTION_N.md` or a `nodes/*.md` file) names a
   test file that is not in that diff, or a test the green run did not execute.
3. The executor's completion report carries a status other than `delivered`, or a non-empty
   `deviations` or `blockers` field.

The reviewer returns a pass or a list of fixes; the executor (re-dispatched) applies them, then
the suite runs once more. On a graph, the risk rule maps onto the verify nodes named in
`graph.md`'s decisions; at most one review-fix round, never more.
## Project Creation

If the plan calls for creating a new project, determine the path from `~/.plastic/config.yml`
`project_roots` or the intent context, confirm the path with the user (the one human
interaction added mid-delivery), invoke `plastic-project-creating`, and continue from the
project directory on the tactical intent.

## Permission Model - Safe-by-Default

Prefer non-destructive routes: rename instead of drop, additive migrations plus backfill, move
files instead of deleting them, feature flags off instead of removed code, a backup before a
migration. When a destructive action on an existing project has no safe alternative, log it in
`## Insights`, notify the user ("Blocked on destructive action: ..."), and STOP unless
`--skip-permissions` was given, in which case log and proceed. During initial project creation
every choice is non-destructive and the team has full autonomy.

## Completion

Read `../plastic-conventions/references/completion-and-done.md` for what "intent done" means.

1. This is the merge gate: verify every checklist item is checked, verify tick-versus-diff against the diff, and confirm the suite is green once on the branch.
2. Write `outcome.md` from `~/.plastic/templates/outcome.md` with `disposition: delivered`,
   `## Delivered` as the labeled table whose row labels match the action-file headings (317a).
3. Release, if configured: match the working directory against `~/.plastic/projects.yml`, read
   `project.yml`'s `release` block, and act on `on_complete` (`commit`, `commit_and_push`,
   `manual`), `verify` (green proceeds; red follows `on_red`: `fix_and_retry` up to twice,
   `stop`, or `manual`), and `on_green` (delegate entirely to `plastic-releasing`).
4. Review `## Insights` for observations that should become future intents; create them through
   `plastic-intent-creating` and update `chain`.
5. Close through `plastic-intent-ending`, which runs `scripts/end-intent`: outcome, INDEX,
   savepoint, the store commit, and the disarm (the worktree released, `delivery.lock` cleared,
   the session pointer back on the day ledger), then the QMD reindex last and the single owner
   report. Pass `--session` and `--index-note`:
   ```bash
   ruby ~/.plastic/scripts/end-intent --store <store_path> --id <ID> --disposition delivered \
     --session "$CLAUDE_CODE_SESSION_ID" \
     --index-note "<what shipped>; <suite result>"
   ```
   Exit 4: a live foreign session holds the lock. 5: the worktree is dirty (commit first, or
   pass `--discard-worktree-changes` deliberately). 3: the lock survived the disarm
   (`/plastic-doctor check the lock status`). 6: the structure check refused. Never leave an
   orphaned worktree; run `git worktree prune` on a stale reference.
6. Print `ruby ~/.plastic/scripts/report-screen delivered <intent_dir>` once (D15/331f), and
   `report-screen state` at each of the five triggers in `references/human-report-contract.md`
   (a review verdict, a blocker, a merge/release, or an owner status ask; a mid-batch ask
   instead runs `report-screen session <tier_root> --session "$CLAUDE_CODE_SESSION_ID"`, intent
   330). Print each as the first characters of the reply: nothing before it, no fence, or the
   hook cannot paint it.

## Error Handling

If the team gets stuck (an unresolvable gap, a missing dependency, a suite that stays red):
log the blocker in `## Insights`, make sure `savepoint.md` reflects the state, notify the user
("Blocked on intent [ID] - [name]: ..."), and STOP. Never work around a blocker in a way that
leaves the project broken.

## References

- Read `references/agent-architecture.md` for the team model, the risk list, the headless note,
  and the solo fallback when dispatching or when a harness has no agent dispatch.
- Read `references/human-report-contract.md` for the three report screens and the five
  triggers before printing the How or Completion screen above.
- Read `references/agent-report-contract.md` for the completion report format when reading a
  dispatched agent's return or synthesizing one.
- Read `references/end-tail.md` for what `Arm.disarm` does at the End tail and why the reindex
  runs last, before closing an intent.
