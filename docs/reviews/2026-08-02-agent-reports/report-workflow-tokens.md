# Agent report: workflow and instruction layer (workflow-tokens)

**Verdict.** Plastic's mechanism layer (gates, locks, `end-intent`, the validator) is well engineered and earns its bytes. Its instruction layer does not. The system carries **521,547 B / ~130k tokens of shipped instruction**, injects **20,039 tokens before any work starts**, and burns **~182,700 process tokens on a medium delivery, 78x a no-Plastic baseline**. A one-line typo fix costs **52 steps, 6 subagent dispatches, 21 file writes, 14 gate evaluations, 11 lock operations, 3 commits and 6 human touchpoints**.

Root cause: **every gate in Plastic is a refusal, and every advance is prose.** No hook, script, or state file ever tells the loop what to do next, so the sequence lives in the model's context (PLASTIC.md 53KB, auto/SKILL.md 24KB, re-read every session and background agent).

## Findings ranked by impact

| # | Finding | Cost today | Fix | Saving |
|---|---|---|---|---|
| 1 | Session boot re-injects PLASTIC.md whole; 61% situational | 8,152 tok/session x 7 bg sessions = 57,000 tok/delivery | Split into always-on core (~5,200 tok) + on-demand sections | 31% of all process overhead |
| 2 | Advance logic is prose, not a driver script | 371 lines auto/SKILL.md + 796 PLASTIC.md held in context | `scripts/next-step <dir>` emitting JSON; inputs already exist in bridge.rb:456-517 | ~15 judgment steps become lookups |
| 3 | Report contracts mandate output nobody reads | 9,989 B instruction driving 2,000-2,500 output tok/delivery | Delete both contracts + 10 Announce/Notify mandates | Largest per-delivery output cut |
| 4 | Tier S does not reduce ceremony | Skips 9/52 steps (17%), all agent boots; 0% of gates/files/asks | Tier must cut files and gates, or be honest it only cuts depth | Small work stops paying large-work overhead |
| 5 | The intent graph is write-only | 3,675 LOC maintained vs ~45 LOC consumed (80:1); `## Links` = 188,549 B, 10% of every intent file | Build the consumer: 2-hop context routing, ~150 LOC | 3-8k tok/intent + real quality gain |
| 6 | Skills duplicate each other / restate base competence | 66% of 130k instruction tokens redundant | 6 merges + 6 deletions | 103,300 B removable of 221,140 B (47%) |
| 7 | Two "hard" gates advisory in the normal case | Code gate auto-only (bridge.rb:1104); lock/worktree gates `solo_allow` solo | Gate on artifact presence, not mode | Restores documented invariants |
| 8 | 6 bash shims + ~14 ruby processes fork per file write | ~140 ruby processes for a typo fix | Merge 5 PreToolUse hooks into one dispatcher | ~130 processes per trivial delivery |

## 1. Token economics

Boot floor before any work: **80,157 B / 20,039 tokens** (PLASTIC.md 13,389 tok + 36 skill descriptions 3,349 + agent descriptions 695 + repo CLAUDE/AGENTS 2,183 + banners 422).

PLASTIC.md: 39.1% needed every session (5,237 tok); 60.9% situational (8,152 tok) — biggest situational blocks: WORK vs MAINTENANCE (9,484 B), Agent Models and Dispatch (8,139 B), lock-mechanics head of Delivery Isolation (6,839 B).

Per medium delivery, auto mode, stage-per-background-agent (each stage re-fires SessionStart):
- Session boot x7: 140,275 tok; skill loads 33,820; role files 3,781; spawn preambles 2,655; per-turn hook injections 2,050 → **~182,668 process tokens** vs 7,909 tokens of delivered artifacts.
- No Plastic baseline: 2,308 tok (1x). Plastic with Task subagents: 97,661 (42x). Plastic with bg agents (actual rule): 180,530 (**78x**).
- 77% of overhead is session boot; 53% of all process tokens is PLASTIC.md injected 7 times.
- Doc bug: docs/reference/harness-adapters.md:117 contradicts :126 (PLASTIC.md does NOT auto-inject into Task subagents; :126 is right).

Ten heaviest instruction files: auto/SKILL.md 24,656 B; PLASTIC.md Delivery Isolation section 21,829 B (always-on); releasing 15,688; faux-advisor 14,822; skill-creating/references/hooks.md 13,085; advisor-protocol.md 12,771; doctor 9,782; intent-executing 9,757; PLASTIC.md WORK vs MAINTENANCE 9,484 (always-on); dashboard 9,455. Only the two always-on rows are situational content = 7,828 tok paid by every session for nothing.

## 2. Workflow shape

Outer loop is **Build/Observe/Repeat** (docs/architecture.md:13) — zero hooks, zero exit codes, zero persisted state; `## Insights` declared its feed, nothing reads it programmatically. Documentation, not mechanism.

Inner lifecycle (real, gated): Start(intent-starting/lock fix) → What(create-gate) → Why(gate-check `## Intent`) → How(real spec, real plan + has_real_action?) → Exec(code/worktree/bash/lock gates) → Done(end-intent, exits 1-6).

One-line typo fix, tier S, auto: **52 steps, 6 dispatches, 14 gates, 21 file writes, 8 savepoint appends, 11 lock ops, 3 commits, 1 mandatory ask + 5 briefings, ~140 ruby processes.** Medium feature: ~78 steps, 13 dispatches — 5x work costs 1.5x steps; overhead flat, hurts small work most.

Tier S vs L: steps 52 vs 61 (-15%), dispatches 6 vs 8; gates 14 vs 14 (0%), files 9 vs 9 (0%), ledger lines 8 vs 8 (0%), human interruptions 6 vs 6 (0%). Tier stamp is unverifiable (PLASTIC.md:151 "read by the orchestrator, not enforced by any gate or by doctor").

intent-brainstorming/SKILL.md:15-17 hard-gates a design presentation "for EVERY project regardless of perceived simplicity" — forces design review onto a typo.

## 3. Graph engineering

458 intents across stores; 72% with sources, 43% with chain, 13% orphans. Plastic store topology: 580 edges, median degree 2, giant component 66%, zero dangling refs, zero I1 violations. One sources back-edge; doctor never checks acyclicity despite zettelkasten.md:32 declaring a DAG. Median degree 2 = linked list, not web.

Usage: 21 write/validate/maintain sites vs 5 code read-sites (3 = one function in dashboard.rb; 2 = the graph reading itself). Net external consumers: dashboard.rb:264,322 (value:high label) and :329-333 (unblocked flag, zero entries today). auto/SKILL.md:79 reads one bit (edge set empty?).

Cost/value: 3,675 LOC maintenance vs ~45 LOC consumption (80:1). `## Links` = 188,549 B (10% of every intent file), zero information content (recomputable from frontmatter, read by nothing but its own validator) — an Obsidian rendering cache costing ~47k tokens store-wide. Graph tests 2,493 LOC = 8.9% of suite.

Build priorities:
1. **Context routing** (~150 LOC): BFS depth-2 from sources+chain, rank by hop/tier/recency, inject only `## Outcome`+`## Insights` slices. Needs machine-readable edge weights (exists as prose in intent-linking/SKILL.md:41-44). Saves 3-8k tok/intent, stops re-deriving parent decisions.
2. Duplicate detection at creation (~80 LOC; link_suggestions.rb:106-117 already computes candidates).
3. `/plastic-related <id>` (~40 LOC).
4. Staleness/conflict detection (~120 LOC + `supersedes` edge type; chain conflates continuation with relation, 88/334 edges).
- **Skip dependency scheduling**: data doesn't exist (only 19 edges connect two Future intents; sources = "born from", not "blocked by").
- Cheap fixes: machine-readable edge tier (`sources: [{id, w}]`); acyclicity check in validate_graph (~10 LOC).

## 4. Loops engineering

Every hook is negative (refusal); nothing advances the loop. 19 hook-enforced invariants vs 20 prose-only (including the entire stage sequence, tier sizing, ask-once, never-cut reviewer, model resolution, spawn-preamble, tick-as-you-land, QMD-first).

Three gate holes: (1) bridge.rb:1104 `return nil unless build["auto"]` — guided mode has NO code-before-How enforcement; (2) bridge.rb:1146-1174 solo_allow turns lock+worktree gates into warnings on single-user machines; (3) all gates fail open on own crash (policy, but gate bugs are silent).

Worst stall points (of 25): mandatory auto-or-guided ask (intent-starting:98-107); 5 State/Risk/Call briefings (each a gate in guided mode); stale-lock reclaim requires asking user; end-intent exit 6 → full tail re-run; two unbounded review loops per task (intent-executing:73-78); **PreCompact hook contradicts shipped design** (hooks/savepoint:2-5 orders a 5-step manual savepoint referencing Build/Observe sections that no longer exist — a wasted wrong turn every compaction).

Move control into scripts:
1. `scripts/next-step <dir>` → {stage, next_action, required_artifact, blocking_gate, dispatch_role, model}; derive_stage (bridge.rb:456) + missing_for_stage (:479) already compute every input.
2. `scripts/board-intent <id> --mode` folding INDEX activation + lock fix + arm + discovery (precedent: intent 188's end-intent).
3. `scripts/dispatch-specialist --role R` replacing auto/SKILL.md:147-181.
4. Enforce tier stamp in hook-gate-check spec branch.
5. Reviewer receipt `.reviews/final.json` + doctor check.
6. Make code gate mode-independent (one line; reached_how at :1117 is mode-blind).
7. Merge 5 PreToolUse hooks into one dispatcher (~130 fewer processes per trivial delivery).
8. Retire PreCompact savepoint body → call Bridge.rebuild_savepoint.

## 5. Skill design

38 skills: 221,140 B bodies + 184,217 B references. 4 thin routers (6.4%), 15 procedural (48.9%), 13 bloated (39.2%), 4 script-shaped (5.5%). Own standard (skill-creating:27-40) met by 4/36 files (11%); auto/SKILL.md exceeds its own budget by 24%.

Merges (no capability lost, **50,600 B / 22.9%**): continue chain (delete intent-continuing pass-through; strip project-continuing changelog + roadmap-continuing rationale) 17,600 B; install+update+rollback+uninstall → one lifecycle skill (channel rule verbatim 4x) 16,000 B; brainstorming+grilling (depth param; fixes grilling:62 writing spec.md which speccing owns) 6,000 B; store-curating+store-indexing (783 B byte-identical) 4,400 B; savepoint+locking repair skill 4,200 B; planning generic advice → references 2,400 B. Do NOT merge speccing+planning (speccing is the best-designed file in the repo).

Deletable (**33,824 B**): skill-evaluating 15,339 (generic eval methodology, keep evals.json schema); humanizer 4,765 (belongs in CLAUDE.md/output-style); intent-researching 4,521 (base competence); intent-grilling 4,727; store-curating 3,167; intent-discovering 2,305 (restates agent role file).

Mechanism-replaceable (**~18,900 B**): QMD-first paragraph in 8 skills (~3,000 B) while hooks/retrieval-gate already emits it; Active Intent Gate inlined 3x while skills/_active-intent-gate.md is referenced by zero files; end-intent exit codes in 3 skills (script could print them); doctor/report.md 4,383 B (60% HTML comments) for ~700 B output.

Verified duplication: intent-executing:88-95 and :115-122 byte-identical, restating a close that intent-ending:33-36 forbids restating; :167 acknowledges and keeps it.

Rating: **34% load-bearing / 66% redundant.** Load-bearing: CLI surface (~55KB), filesystem-as-schema (~50KB), ordering constraints from real failures (~35KB), determinism contracts (~20KB), owner preferences (~17KB). Redundant: the system explaining itself to itself (rule archaeology, narration mandates).

## 6. Verbosity audit (output tokens per delivery)

1. Agent report contract (agent-report-contract.md:30-46): 9-field envelope from every specialist; 1,250-2,000 tok. `scripts/agent-report` already synthesizes it deterministically — proof the model version was never load-bearing.
2. Five State/Risk/Call briefings: ~400-500 out + 730 read; auto-mode Call is answered by the writer itself (human-report-contract.md:48-55).
3. Triple-telling at Done: outcome.md + EM-to-CTO report + Done briefing + intent-file stamp; 300-600 tok.
4. Mandatory full-board paste on continue: 600-1,200 tok (dashboard:102-114; hook systemMessage fallback exists at :109-114).
5. Twelve Announce mandates, 15-25 tok each (3 announce the skill's own name, which the harness already displays).
6. Self-exhortation ("This is NOT optional" twice, 27 lines apart, in the byte-identical blocks).

Per-delivery ceremony: **2,500-4,300 output tokens + ~4,000 contract-reading; tier S changes none of it.**

## Single highest-leverage change

Delete agent-report-contract.md (7,086 B) + human-report-contract.md (2,903 B) + the 10 Announce/Notify mandates: 9,989 B instruction and 2,000-2,500 output tok/delivery, at zero cost (outcome.md already truth; agent-report already derives it). Pair with the PLASTIC.md split (57k tok/delivery) and `scripts/next-step` (what makes the split safe). Together: **~40% of process overhead and most ceremony prose cut, without touching a single gate.**
