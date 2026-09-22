---
id: "340"
intent: "G7 of the graph-ready plan (intent 327, Batch 3, needs G3 (336), G5 (338), G6 (339)): Runner core in the harness session. Runner core in the harness session over the Ruby commands: three public verbs, `ready` and `sweep` internal (C29); validation before first dispatch (C9); crash sweep with `reclaimed` lines recording landed commits (C11), live-node extension capped at two per attempt (C6, C30), `MERGE_HEAD` abort at sweep start (C5); ready-set dispatch at concurrency two through native subagents; per-node worktrees off the intent branch with lifecycle through failure states (C31, D32), merge on `done`, conflict inside `files:` is `failed_verification` and outside `files:` is `needs_decision` with the paths (C12); `graph.md` re-read and cycle-checked before each dispatch (C12); kind policies with retry caps (C3); verify nodes as a separate invocation with only the packet on the advisor model, no worktree, any diff fails (C4); the runner runs the tests itself at `done` and writes `suite=` (C18); return is one schema-checked YAML document, unparsable is `failed_verification` (C22); diff outside `files:` is `failed_verification` (C4); findings land as one capped Insight line per node (C27); `needs_decision` stop with an answer command (C26); proposed nodes and edges accepted mechanically or refused with a reason, never into a running node (C8); core integrity check against the hashed manifest after every return (C10); `done` only on code-verified evidence (absorbs 69's six primitives, supersedes 44); rewind command after the runner proves itself (C15)."
sources: ["327"]
chain: ["340a", "340b", "351"]
created: 2026-09-07
author: claude-code
tags: ["project-plastic", "graph-ready", "batch-3", "g7"]
---

## Intent
G7 of the graph-ready plan (intent 327, Batch 3, needs G3 (336), G5 (338), G6 (339)): Runner core in the harness session. Runner core in the harness session over the Ruby commands: three public verbs, `ready` and `sweep` internal (C29); validation before first dispatch (C9); crash sweep with `reclaimed` lines recording landed commits (C11), live-node extension capped at two per attempt (C6, C30), `MERGE_HEAD` abort at sweep start (C5); ready-set dispatch at concurrency two through native subagents; per-node worktrees off the intent branch with lifecycle through failure states (C31, D32), merge on `done`, conflict inside `files:` is `failed_verification` and outside `files:` is `needs_decision` with the paths (C12); `graph.md` re-read and cycle-checked before each dispatch (C12); kind policies with retry caps (C3); verify nodes as a separate invocation with only the packet on the advisor model, no worktree, any diff fails (C4); the runner runs the tests itself at `done` and writes `suite=` (C18); return is one schema-checked YAML document, unparsable is `failed_verification` (C22); diff outside `files:` is `failed_verification` (C4); findings land as one capped Insight line per node (C27); `needs_decision` stop with an answer command (C26); proposed nodes and edges accepted mechanically or refused with a reason, never into a running node (C8); core integrity check against the hashed manifest after every return (C10); `done` only on code-verified evidence (absorbs 69's six primitives, supersedes 44); rewind command after the runner proves itself (C15).

## Context

Batches 1 and 2 of the graph-ready plan built every part a runner needs and no runner. `graph.md`
and `nodes/` describe the work (334). `savepoint.md` carries closed-state transition lines that
refuse what the graph does not allow (335). `ready-set` computes the ready order, batches and
critical path from the edges (336). `node-packet` builds a node's whole input as deterministic,
hashed bytes (338). `outcome-report` renders the close from the ledger (339). The kill gate ran
on 2026-09-10 and found the criterion holds: refusals refuse, a killed session resumes from
`ready`, `packet` and `node-transition` alone, and a generated `outcome.md` reproduces byte for
byte.

What is missing is the thing that calls them in order. Today a human orchestrator types the
commands, decides when to sweep, eyeballs the diff, remembers the retry cap, and merges by hand.
Every refusal the ledger enforces is real, but nothing drives the loop, so a graph-era intent
still costs a session of hand-holding and no node can run unattended.

G7 is that loop. It is deliberately not a daemon: ruling D42 keeps the runner inside the harness
session using native dispatch, because the two harnesses Plastic must serve differ in exactly one
place, how a subagent is spawned, and a standalone Ruby runner would have to own that difference
forever. So the Ruby side does everything a Ruby process can do deterministically, and hands the
session one machine-readable dispatch plan per turn.

Absorbed from intent 69, the six loop primitives, each answered by a part of this runner rather
than by a new mechanism: automations become `runner step` called in a loop; worktrees become the
per-node worktree lifecycle; skills shrink to three verbs (G8); sub-agents stay the harness's own
native dispatch; connectors become the packet, which is the only interface an executor sees; and
external state is the ledger, which was already there. Intent 44 is superseded by the same move.

### Decisions

- D1. Three public verbs on one command, `scripts/runner`: `step`, `status`, `answer` (C29).
  `ready` and `sweep` are subcommands of the same binary, working and callable, but absent from
  the skill body so the published surface stays three. `rewind` (C15) ships as a sixth, internal,
  confirm-gated subcommand: the graph facts it needs are all here now, and publishing it before
  G10 has measured a real run would invite a reset nobody has evidence for.
- D2. `runner step` is one turn of the loop and prints a dispatch plan; the session makes the
  subagent calls. Ruby sweeps, validates, re-reads the graph, absorbs returns, mints leases,
  builds packets, writes `running`, and then prints, per dispatched node, the packet path, the
  model, the worktree path, the kind and the agent role. The session dispatches those, collects
  each return as a file, and calls `runner step --return <node>=<path>` on the next turn. No Ruby
  process ever spawns an agent (D42).
- D3. Concurrency two is a ceiling on `running` nodes, checked in Ruby, not a thread pool. One
  `step` dispatches at most `2 - running` nodes, in `ready-set` order.
- D4. The executor return is one YAML document with a closed schema, parsed by the runner, not by
  `node-transition`. Keys: `node`, `status`, `commit`, `summary`, `findings`, `proposed_nodes`,
  `proposed_edges`, `question`, `reason`. Anything unparsable or off-schema is
  `failed_verification reason=return_unparsable` (C22). This is a deliberate deviation from C22's
  wording, which put the parser in `node-transition`: that command is the field-level refusal
  layer with a stable exit-code contract, and giving it a second input grammar would make its
  refusals ambiguous. The refusal semantics C22 asks for are preserved exactly, one layer up.
- D5. The packet is not extended; the return contract rides in the dispatch prompt. 338's D2 fixes
  five packet blocks and `packet=<sha>` names an exact set of bytes, so the runner appends the
  return-schema instruction to the prompt after the packet rather than into it.
- D6. Work nodes get a per-node worktree at `<repo>/.claude/worktrees/<id>--<slug>--<node>` on
  branch `plastic/<id>--<slug>--<node>`, cut from the intent branch tip. Verify, research and
  decision nodes get none (C4, D29): they produce no diff, so a worktree would only give them a
  place to write one. A new `NodeWorktree` module owns this; `Worktree` stays intent-scoped and
  untouched.
- D7. Node worktree lifecycle through failure states (C31, D32): provisioned at `running`, merged
  into the intent branch at `done` and then removed, KEPT on `failed_verification` and
  `needs_decision` so the evidence survives for the retry or the owner, removed on `superseded`
  and `abandoned`. `sweep-store-worktrees` learns the node branch shape so a crashed run leaves
  no orphan.
- D8. Conflict routing (C12): the merge is aborted on any conflict. Every conflicted path inside
  the node's `files:` is `failed_verification reason=merge_conflict`; any conflicted path outside
  `files:` is `needs_decision` whose question names the paths, because a node that collided
  outside its declared surface is a graph error the owner owns.
- D9. Diff-scope check at `done`, before the merge (C4): a verify or research node with any diff
  at all is `failed_verification reason=diff_on_verify_node`; a work node with a changed path
  outside `files:` is `failed_verification reason=diff_outside_files`.
- D10. The runner runs the tests itself (C18) after a clean merge, in the intent worktree, using
  the project's own verify command, and writes `suite=<runs>/<assertions>/<failures>` on the
  `done` line. A red suite is `failed_verification reason=suite_red`. A test named in the node's
  failure-mode matrix whose file does not exist is `failed_verification reason=named_test_missing`,
  which is C18's refusal of a named test that does not exist.
- D11. Core integrity after every return (C10), before any transition is written: re-hash the
  files listed in `<plastic_home>/manifest.json` and compare, in a new `CoreIntegrity` module that
  doctor's manifest check also calls, so the two cannot drift. Drift stops the step and writes
  `blocked reason=core_integrity` on the Intent subject. `--allow-core-drift` exists and is
  recorded on the line, because Plastic's own repository is the one legitimate drift case and the
  runner has to be able to dogfood itself.
- D12. Kind policy table with retry caps (C3): work runs on the executor model, gets a worktree,
  retry cap 2, tests at `done`, diff allowed inside `files:`. Verify runs on the advisor model
  (D31, D42), no worktree, retry cap 1, no diff. Research runs on the executor model, no worktree,
  retry cap 1, no diff. Decision is never dispatched: a ready decision node stops the loop with
  `needs_decision` and the answer command. The cap counts `failed_verification` lines through
  `ReadySet.failed_verification_count`, which 336 already ships; at the cap the node becomes
  `needs_decision`.
- D13. Extension is not a ledger state (C6, C30). A second `running` line for a live node is
  refused by the transition layer, so an extension cannot be written as one. Sweep records each
  extension as a line in `packets/<node>--a<N>.extensions` next to the packet, carrying the
  observed head sha and the time, capped at two per attempt; the third expiry reclaims regardless
  of new commits. Each extension is printed in the step report, which is what G7b's watch records.
- D14. `reclaimed` records the landed commits (C11): sweep writes the reclaim line, then the
  packet for the next attempt shows those commits under "already landed", which 338 already
  builds. Sweep runs first in every step and aborts the whole step when `MERGE_HEAD` resolves in
  the intent worktree (C5), because a half-finished merge means the previous step died mid-merge.
- D15. Proposals are accepted mechanically or refused with a reason, never into a running node
  (C8, D28, D30). The runner mints the id; a proposed node is scaffolded from its kind's template
  and appended to `## Graph` as planned. A proposed edge is accepted only when both endpoints
  exist, the head is not `running`, and the result stays acyclic; a refusal writes one ledger
  comment naming which of the three failed, and nothing is partially written.
- D16. Findings land as one capped Insight line per node per return under `### Findings` (C27),
  200 characters, through the guarded append; the rest of the return is discarded (D45).
- D17. Validation before the first dispatch (C9): the full `WorkGraphValidator` runs when the
  ledger holds no `running` line for any node, and refuses to dispatch when it fails. Every step,
  first dispatch or not, re-reads `graph.md` and cycle-checks before dispatching (C12).
- D18. `done` is written only on code-verified evidence: a schema-valid return saying done, clean
  integrity, in-scope diff, existing named tests, a clean merge, and a green suite. Every other
  path writes `failed_verification`, `needs_decision` or `blocked`. This is what absorbs 69's
  primitives into one refusal.
- D19. Deferred to 340a: the timer, the stalled and done-unreported classification, the launchd
  job. Deferred to 340b: the Claude Code and Codex adapters, per-kind agent definitions with
  `tools:`, the permission deny rule, the Stop hook (C32) and the PreCompact hand-off. The runner
  prints a harness-neutral dispatch plan and knows nothing about either harness.

### Decisions from the plan review meld (2026-09-10)

The adversarial plan review returned REVISE with eight blockers, sixteen majors and five minors
before any code was written. The report is at `resources/review--plan-2026-09-10.md`. Every finding
is melded; nothing was dropped. These twelve decisions are what the meld changed.

- D20 (blocker 1). `gates=` is a required field on `done` and `failed_verification` and appeared in
  no decision and no matrix row, so every terminal transition would have raised before touching the
  file. The runner writes `gates=` as a plus-joined list of the checks that actually ran, from the
  closed set `integrity`, `schema`, `scope`, `named_tests`, `merge`, `suite`. A `done` line carries
  every check its kind runs; a `failed_verification` line carries the checks that ran before the
  refusal, so the line says how far the gate got.
- D21 (blocker 2). An empty ready set is not completion. `ReadySet` drops an unready node from
  `ranked_ready` whether it is done or blocked, so a stalled run would have reported the intent
  finished. The runner reports complete only when every declared node resolves to a terminal state,
  and otherwise reports stalled and prints each unfinished node's blockers, which
  `build_node_views` already carries.
- D22 (blockers 3, 4, and major 20). There are two caps and both are real. The runner's soft cap
  from D12 parks a node at `needs_decision`; `ReadySet::DEFAULT_CAPS` stays the transition layer's
  hard backstop and `node-transition` is not changed. Because `READY_PRIOR_STATES` holds only
  `planned` and `failed_verification`, a parked work node had no way back. `runner answer` unparks
  one: below the hard attempt cap it writes `planned`, and at or above it, it supersedes the node
  and mints a successor carrying the same body, files and edges. Superseding is the only exit the
  shipped ledger semantics offer, because only `done`, `superseded` and `abandoned` reset the
  attempt count, and it is exactly what 327's D14 and D20 mean by supersede. `rewind` uses the same
  respin rather than writing `planned`.
- D23 (blocker 5). The packet's "where to work" block reads `Arm.worktree_block`, which names the
  intent worktree, so an executor obeying its packet would have committed on the intent branch and
  left the node branch empty. The runner injects a node-scoped `worktree_reader:` into
  `NodePacket.build`, which already takes one, so the packet names the node worktree and branch
  without touching 338 and without extending the packet.
- D24 (blocker 6). `NodeWorktree` owns its own merge. `Worktree.merge_branch` resolves its target
  as the main checkout's current branch, so reusing it would have merged node work into `alpha`.
  The merge runs as `git -C <intent worktree> merge --no-ff <node branch>`, conflicted paths come
  from `git diff --name-only --diff-filter=U` before the abort, and `merge_branch` is left alone.
- D25 (blocker 7). Each node registers its own new libs in `InstallerCore.core_files`.
  `install_sync_test` fails the moment a `scripts/*` file requires a lib the list does not carry,
  so deferring registration to n7 would have left the suite red from n1 to n6. Every node from n1
  to n6 carries `scripts/lib/installer_core.rb` in its `files:`.
- D26 (blocker 8). `WorktreeSweep` is not taught node branches. It globs the store-worktree tree
  intent 178 retired, derives a `plastic-store/` branch, and resolves intent dirs by exact name, so
  teaching it would have taught the wrong module in the wrong tree. A runner-owned reaper in
  `NodeWorktree` sweeps `<repo>/.claude/worktrees/`, removes a terminal node's worktree, and spares
  an unmerged node branch. This is a correction to 327's C31 one level up in the design; it is
  recorded here for G8 to carry into the doctrine.
- D27 (major 9). The step order is `MERGE_HEAD` abort, absorb, reclaim, validate, dispatch. Only
  the abort has to come first. Sweeping before absorbing would have reclaimed a node whose executor
  finished just past its lease and thrown the work away. The reclaim pass never touches a node
  named in a `--return` of the same step.
- D28 (major 14). `RunnerCore.render_status` re-renders `graph.md` `## Status` through
  `GraphFile.write_status` after every transition the runner writes. That function had no
  production caller anywhere, so the table the graph calls rendered would have read `planned`
  forever.
- D29 (majors 12, 17, 18, 23). Synthesized text and sub-schemas, all pinned rather than left to the
  implementer: the retry-cap question and the conflict question that names the paths, because
  `needs_decision` requires `question=`; the `proposed_nodes` entry shape (`kind`, `title`, `needs`,
  optional `files`, optional `budget`) and the `proposed_edges` entry shape (`from`, `to`); the
  minted id substituted into all three places the node template hard-codes `n1`; and `suite=none`
  with `gates` recording `suite:absent` when the project record names no verify command.
- D30 (majors 11, 15, 16, 21, and minors 25 to 29). Recovery rules. A packet file for an attempt
  with no `running` line is rebuilt with `force`, because `NodePacket.build` otherwise refuses the
  attempt forever. An append that fails after a landed merge reports the merge commit and leaves the
  node recoverable. The node worktree is removed only after the `done` line lands. A `delivery.lock`
  refusal is a named step outcome that prints the re-arm command. The `MERGE_HEAD` abort prints the
  command that clears it. The drift field key is `core_drift`. The return file is kept beside the
  packet as `packets/<node>--a<N>.return`. The lease heartbeat runs after the abort, not before it.
  The runner reads the file-overlap refusal from `ReadySet` and never reimplements it.
- D31 (major 24, probe 34). Five sequential executor dispatches, and `plan.md` and `ACTION_1.md`
  state the same five. The suite runs once per absorbed return, at the measured baseline of 3778
  runs and 19341 assertions in 277 seconds; that cost is stated rather than optimized, and G10 is
  where it gets measured against a cheaper shape. Nothing in this intent shells `timeout`, which
  this machine does not have.

## Outcome
(the result — implementation details, deliverables)

## Insights
(observations captured throughout — raw material for future intents)
2026-09-10T06:22:41Z · Why · claude-code — (autonomous) The runner cannot express an extension as a ledger state: node-transition refuses a second running line for a live node, correctly, so an extension became a per-attempt file beside the packet. A closed state machine is a constraint on the loop that drives it, not only on what it records.
2026-09-10T06:22:41Z · Why · claude-code — (autonomous) C22 put the YAML return parser inside node-transition. Deviated: that command is the field-level refusal layer with a stable exit-code contract, and a second input grammar would make its refusals ambiguous. The runner parses; the refusal semantics are unchanged, one layer up.
2026-09-10T06:22:41Z · How · claude-code — (autonomous) 327's C31 is wrong one level up: sweep-store-worktrees globs the store-worktree tree intent 178 retired and derives a plastic-store/ branch, so it can never see a node worktree. G8 should carry the correction into the doctrine, not just 340.
2026-09-10T06:22:41Z · How · claude-code — (autonomous) The adversarial plan review paid for itself twice over before a line of code: gates= is a required ledger field that appeared in no decision and no matrix row, so every terminal transition would have raised, and install_sync_test would have been red from n1 to n7 under the original registration order.
2026-09-10T06:33:33Z · Exec · plastic-executor (autonomous) — test/install_packaging_test.rb's require-closure guard is a naive source-text regex over require_relative "...": it matches ANY literal occurrence of that pattern in the file, including inside a comment (not just real require_relative calls). A dynamic lazy-require (require_relative(File.join("lib", var))) correctly falls outside it since there is no inline quoted literal, but a doc comment that quotes an example like require_relative "lib/..." trips the same guard as if it were real code. When writing a lazy-loaded verb dispatch table, keep example require paths in comments unquoted or paraphrased.
2026-09-10T13:43:27Z · Exec · plastic-executor — n5: NodePacket#where_to_work_block prints the STOP no-lease directive whenever worktree_reader reports provisioned:false, which is by design for verify and research kinds (C4). The stop should key off lease presence, not worktree presence; the fix belongs in node_packet.rb (intent 338), outside n5's files.
2026-09-10T13:43:27Z · Exec · plastic-executor — n5: the two retry caps must not be conflated. RunnerPolicy's soft cap counts failed_verification lines only and parks the node at needs_decision; ReadySet::DEFAULT_CAPS is the hard backstop counting running lines since the last terminal line and drops the node from the ready set until an owner acts. The stalled report names the hard backstop separately.
2026-09-10T13:50:13Z · Exec · plastic-enforcer — n6 carries a running line (packet=bde4259df9be, expires 2026-09-10T16:43:35Z) whose executor dispatch was interrupted before it started, so no work was done under that lease. node-transition correctly refuses a reclaim before expiry. A resuming lead should re-dispatch n6 on the already-minted a1 packet and absorb its return against that same lease, or wait for expiry and reclaim.
2026-09-10T22:14:28Z · Exec · plastic-enforcer — RunnerDispatch#dispatch_one calls NodePacket.build without budget_tokens:, so every runner-built packet is capped at DEFAULT_BUDGET_TOKENS 8000 and a node's declared frontmatter budget: is inert. At 8000 the cut ladder silently drops the whole knowledge hop (hop_tokens=0) and cuts Insights; n6's declared budget 140000 renders 8237 tokens with the hop intact. scripts/node-packet has the same hole: it passes NodePacket::DEFAULT_BUDGET_TOKENS when --budget is absent instead of letting build fall back to the node block's parsed budget. Fix belongs to the v1 review meld, since runner_dispatch.rb is outside n6's files.
2026-09-10T23:32:46Z · Exec · plastic-enforcer — HookMessageDisplayTest#test_concurrent_session_blanks_and_buffers_every_chunk is flaky under the parallel full suite: it failed once at 3950/19581/1/0 (a chunk passed through as raw Markdown), then passed in isolation (83 runs, 0 failures) and passed again in the next full run at 3950/20006/0/0. The assertion count differing by 425 between the failing and passing full runs points at fork-parallel timing, not at a code change; hooks/ is untouched by intent 340. Worth a real fix or a serialization pin before it costs another node a gate.
2026-09-10T23:52:03Z · Exec · plastic-executor (autonomous) — The n7 dogfood against an authored scratch intent (status/sweep/step, resources/dogfood--runner-2026-09-10.md) found two real defects in scripts/runner outside n7's scope: 'sweep' is unreachable from the CLI (dispatch_lazy has no case for it even though RunnerSweep.run is a complete standalone entry point), and 'step' crashes with NoMethodError: undefined method 'opt_all' on every call, before any dispatch work runs; no test exercises the runner step CLI end to end, which is how a green 3955/20025/0/0 suite shipped over it.
2026-09-11T00:19:28Z · Exec · plastic-enforcer — n7's dogfood found what five green node gates missed: runner step raised NoMethodError on opt_all on every invocation and runner sweep never reached a dispatcher. Both slipped through because every runner test drove the module API (RunnerDispatch.dispatch, RunnerSweep.run) and none drove scripts/runner as a subprocess past argument parsing. The suite proved the engine and never turned the key. n8 fixed both and pinned the class of bug with a structural test walking Runner::VERBS. Rule for every future CLI node: one end-to-end subprocess test per public verb, or the verb is unproven.
2026-09-11T03:49:52Z · Exec · plastic-enforcer — Two adversarial verify passes on this runner each found blockers a green suite had hidden, and the second found that the first meld introduced two more. The pattern is consistent: every new blocker sat on a path the previous meld had just created. Writing the executor's own prose into a ledger field met a field validator that refuses newlines; wiring proposals into absorb made an unguarded graph re-read reachable; wrapping an atomic rewrite in an append guard made the rename defeat the lock. New production surface written in one pass carries new failure modes, so a meld of a review is itself review-worthy, and budgeting one verify pass per intent underestimates a meld that touches the gate the review was about.
2026-09-11T04:18:53Z · Exec · plastic-enforcer — Merging alpha in went red on n7's test_no_version_bump, which pinned the literal 2.0.0-alpha.18 as the unbumped value; alpha had since released 2.0.0-alpha.19. A version guard that hard-codes a version goes red on the next release rather than on the bump it exists to catch. The reference must be the branch point (git merge-base HEAD alpha, then the version at that commit), which still catches a bump riding in on the branch and survives every later release. Fixed by the lead as part of resolving the merge and verified by bumping all three version files and watching the new assertion fail. Any test that pins a moving repo-wide constant has the same defect.

## Links
- [[327--graph-of-work-under-the-roadmap|Research and thinking: the graph of work under the roadmap name. Roadmap stays the human-facing word; underneath, intents carry a dependency graph: the existing dashboard ready rule (all sources completed) wired into the roadmap queue, an after edge for sibling order, computed batches with hand batches as override, a cycle check at creation, supersedes edges and a computed lineage for how an intent was reshaped (D20), and archive as a view. Ties 224 (research, done), 241 (repair and guard), 282 (roadmap graph research), 132 (archive dir) into one design; rulings D15, D16, D17, D20, D24 from 323]]
- [[340a--delivery-watch|G7b of the graph-ready plan (intent 327, Batch 4, needs G7 (340)): Delivery watch. Delivery watch: the runner's sweep and ready-set step on a timer over disk truth (local `/loop` on Claude Code; SessionStart sweep and an optional launchd job on Codex), stalled and done-unreported classification (melds 328); unattended start stated honestly: Codex yes through the Ruby loop, Claude Code no under Q6; the watch records the dispatches it triggered (C30).]]
- [[340b--harness-adapters|G7c of the graph-ready plan (intent 327, Batch 4, needs G7 (340)): Harness adapters, Claude Code and Codex. Harness adapters as two nodes (D46): Claude Code (background subagent dispatch, agent definition per kind with `tools:`, permission deny rule for the engine directories, Stop hook armed from live lock ownership once the owner rules on it, PreCompact hand-off carrying `runner-step` output; C25, C32) and Codex (`node-run` over `codex exec`, sandbox `read-only` for verify and research, `workspace-write` with `writable_roots` for work, `runner --until-empty` with two subprocesses; C17, C25); cross-harness resume recorded as a ledger line (C34, D46); melds 69a.]]
- [[351--graph-era-close-and-runner-defects|Graph-era close and runner defects found during Batch 3: (1) outcome-report reads the first node's suite count instead of the last, so every graph intent's outcome.md understates its suite (339's outcome_report.rb; 340 corrected by hand); (2) node-packet prints the no-lease STOP directive whenever a node has no worktree, by design for verify and research kinds, so it fires on healthy nodes and should key off lease presence (338's node_packet.rb); (3) plastic-lock delegate refuses after a reclaim that changes the owner key (same-key reclaims work, narrowed 2026-09-10); (4) the close gate must generate outcome.md for graph-era intents (336 and 338 closed with hand-written files; only 339 and 340 shipped generated ones); (5) a hand-appended done line without holder= wedges a node because NodeLedger.attributed? never sees it; (6) end-intent writes em dashes into INDEX entries; (7) HookMessageDisplayTest#test_concurrent_session_blanks_and_buffers_every_chunk is flaky under the parallel suite (failed once in 340 n6, passed in isolation and on rerun).]]
