# Plastic System Review: speed, workflow, market, and direction

Date: 2026-08-02. Subject: Plastic v1.8.0 (source at `~/apps/personal/plastic`, installed at `~/.plastic`).

How this review was made: three parallel research agents (code and runtime, workflow and instruction layer, market landscape) plus direct measurements by the coordinating session. All analysis was read-only. Every latency and size number below was measured on this machine (arm64 macOS, Ruby 4.0.3 with YJIT) unless marked as an estimate. The review was run outside the Plastic workflow, by explicit owner permission, so the findings are not shaped by the system under review. The three full agent reports are archived alongside this file in `resources/` style detail; this document is the synthesis and the decision surface.

---

## 1. Verdict

1. **The mechanism layer is good. The instruction layer is the problem.** Gates, locks, `end-intent`, the validators, and the 1,837-test green suite are real engineering and worth keeping. The prose layer around them carries roughly 130k tokens of shipped instruction, of which about two thirds is redundant, and it is what makes Plastic feel slow and talky.
2. **Speed is an architecture problem, not a language problem.** The same three write-gates run in 970ms today and in 251ms after two mechanical fixes. A Go or Crystal rewrite would buy about 11ms per process spawn while roughly 600ms per edit sits in bash shims, RubyGems boot, and a 526ms `qmd status` probe fired on every file read. Stay on Ruby. Numbers in section 3.
3. **The Judo principle is currently inverted for small work.** A one-line fix costs 52 steps, 6 subagent dispatches, 14 gate evaluations, and about 183k process tokens on a medium delivery (78 times a bare-agent baseline). Tier S removes 17 percent of the steps and 0 percent of the gates, files, and human asks.
4. **The intent graph is written but not read.** About 3,675 lines of code maintain it; about 45 consume it. Its unbuilt consumer (context routing from the graph into the working agent's prompt) is the single biggest quality win available.
5. **The market position is real and the window is open.** "Intent-driven development" as a term is claimed by others, but nobody with traction ships intent as a typed, durable artifact with a lifecycle. The commercial market went to the pull request and the session and skipped the middle. The play is to be the reference implementation, prove it with the benchmark nobody in the category has, and distribute through plugin marketplaces.

---

## 2. What Plastic is good at, and what holds it back

### Strengths (verified, not aspirational)

| Strength | Evidence |
|---|---|
| Deterministic enforcement that prompts cannot skip | 19 hook-enforced invariants; write-time create gate; stage gates with typed exit codes. Near-unique in the field: every popular competitor enforces process through prompts, which models ignore |
| A real, green, hermetic test suite | 1,837 runs, 6,406 assertions, 0 failures. None of the popular competitors ship anything comparable |
| Intent as desire, with idea development | Parked future intents, research deposits, revival. Every major competitor (Spec Kit, BMAD, GSD, Taskmaster, OpenSpec) assumes the idea already exists when work starts |
| Outcome as truth, including abandonment | `outcome.md` records what actually happened. Every competitor's record ends at "merged". This is the audit-trail story companies will pay attention to |
| Zettelkasten graph store | Unique at any scale. The closest neighbor (memex) has 139 stars. Beads has a dependency DAG, which is a different thing |
| The advisor role | A frontier model consulted only where reasoning is hardest. No competitor has a tiered-reasoning role at all |
| Progressive disclosure, structurally | Always-on cost of the skills tree is only ~3.7k tokens of descriptions; bodies load on trigger. The structure is right even where individual files are overweight |
| Honest engineering culture | Fail-open policy is deliberate and consistent; known bugs are recorded; the docs warn about their own traps |

### Drawbacks (ranked by how much they hurt)

| # | Drawback | Measure |
|---|---|---|
| 1 | Process overhead dwarfs work for small intents | 52 steps and ~140 Ruby processes for a one-line fix; 78x token overhead on a medium delivery |
| 2 | Hook latency on every single tool call | 854ms per Write/Edit, 704ms per Read/Grep/Glob, ~966ms per Bash, 1,226ms per user prompt |
| 3 | Session boot injects everything, always | 55,558 bytes (~13.9k tokens) of PLASTIC.md into every session and every background agent; 61 percent of it is situational content that a plain guided delivery never uses |
| 4 | Ceremony output nobody reads | 2,500 to 4,300 output tokens per delivery of mandated reports, briefings, and announcements; the auto-mode "Call" line is answered by its own writer |
| 5 | The graph is bookkeeping, not memory | 80:1 maintain-to-consume code ratio; `## Links` sections are 10 percent of every intent file and are read by nothing except their own validator |
| 6 | Concurrency model has real holes | No `flock` anywhere; SessionStart wipes an armed bridge on every resume; `disarm_auto` trusts the cache over the lock file. Section 8 |
| 7 | Two "hard" gates are advisory in the normal case | The code gate only applies in auto mode; lock and worktree gates soften to allow-with-warning on a solo machine |
| 8 | No traction and no 90-second surface | 9 GitHub stars in a field where the relevance floor is ~5k; the systems that win adoption are understandable in 90 seconds |

---

## 3. Speed: measured, with ranked fixes

### What runs when (measured)

| Event | Hooks fired | Cost |
|---|---|---|
| Session start | session-start, check-update | 1,020ms + 55.5KB context |
| Every user prompt | continue, future-intent-check, auto-arm, qmd-search | 1,226ms |
| Every Write/Edit | code-gate, lock-gate, savepoint-pre, links-gate, create-gate, then gate-check | 854ms |
| Every Read/Grep/Glob | retrieval-gate | 704ms |
| Every Bash | bash-gate + retrieval-gate | ~966ms |
| Statusline | statusline | 66ms |

Over a typical delivery (about 50 edits and 150 bash/read calls) this is more than a minute of pure hook latency, before any model thinking.

### Where the time actually goes

1. **A 526ms `qmd status` subprocess on every read.** `hook-retrieval-gate:95` calls `QmdSync.fresh?`, which shells out to `qmd status`, on every Read, Grep, Glob, and Bash call, purely to decide whether to print an advisory hint that by design never blocks. A per-session or 60-second cache removes ~590ms from every retrieval call.
2. **Bash shims that re-parse the same JSON up to four times.** `hooks/code-gate` spawns Ruby four times: three `ruby -rjson` one-liners each parse the same stdin blob to pull one field, then a fourth runs the gate. One Write/Edit spawns about 10 Ruby interpreters, 8 of which exist only to re-parse JSON the target script could read itself. Seven shims contain a literal `JSON.parse(STDIN.read)`.
3. **RubyGems boot, 39ms per spawn, free to remove.** `ruby -e ''` costs 55ms; `ruby --disable-gems -e ''` costs 16ms. Every runtime require in `scripts/` is stdlib. Verified that gates run correctly under `--disable-gems`.
4. **The /tmp bridge glob.** `discover_bridge` JSON-parses every `/tmp/plastic-*.json` (17 present right now) in every gate process: about 100 JSON parses per single edit.
5. **`hook-session-start` requires all of `doctor.rb`** (3,016 lines, +126ms) to run one health check.

### The headline measurement

Same three write-gates, identical work, five iterations: **970ms today, 251ms** with direct invocation, `--disable-gems`, and no JSON re-parse shims. A 74 percent cut with zero rewrite and zero semantic change.

### Ranked speed fixes

| # | Fix | Saving | Effort |
|---|---|---|---|
| 1 | Cache QMD freshness per session or with a short TTL | ~590ms on every retrieval call | S |
| 2 | Delete the 18 bash shims; hook scripts read stdin JSON directly | ~250-300ms per edit, kills the bash 3.2 constraint entirely | S |
| 3 | `--disable-gems` on all hot hook invocations | ~390ms per edit | XS |
| 4 | Merge the 5 PreToolUse write hooks into one process with one shared context | 4 spawns per edit; also closes divergence between gates | M |
| 5 | Stop requiring `doctor.rb` from session start; split doctor so `--core` loads only its checks | ~126ms per session | XS |
| 6 | Index /tmp bridges by key instead of glob-and-parse-all | 10-40ms per gate | S |
| 7 | Split the PLASTIC.md injection (see section 4) | ~8k tokens per session | M |

Fixes 1-3 are mechanical, take a Write/Edit from 854ms to under 250ms and a Read from 704ms to about 50ms, and can land in one small batch. The test suite (165s at 6 percent CPU duty cycle, subprocess-bound) speeds up from fix 3 as well.

---

## 4. Workflow and token economy

### The boot bill

Before the user types anything, a session carries 20,039 tokens of Plastic overhead: the whole of PLASTIC.md (13,389), 36 skill descriptions (3,349), agent descriptions (695), repo CLAUDE/AGENTS files (2,183), banners (422). PLASTIC.md itself is 39 percent always-needed and 61 percent situational (the WORK vs MAINTENANCE rules, the agent-model dispatch tables, and the lock mechanics are the three biggest blocks, and none of them fires on a plain guided delivery).

Because the standing rule is one background agent per stage, each stage re-fires SessionStart and re-pays the whole bill. A medium auto delivery measured out at:

| Line item | Tokens |
|---|---|
| Session boot, 7 sessions | 140,275 |
| Skill loads | 33,820 |
| Agent role files + spawn preambles | 6,436 |
| Per-turn hook injections | 2,050 |
| Total process overhead | ~182,700 |
| The delivered artifacts themselves, for contrast | 7,909 |

Bare agent with a repo AGENTS.md: 2,308 tokens (1x). Plastic with Task subagents: 42x. Plastic with background agents, the actual configuration: **78x**. Fifty-three percent of all process tokens is PLASTIC.md injected seven times.

### Ceremony that produces nothing

- The agent report contract mandates a 9-field envelope from every specialist (1,250-2,000 output tokens per delivery). The giveaway: `scripts/agent-report` already synthesizes the same report deterministically from the intent directory when an agent fails to produce one. The model-written version was never load-bearing.
- Five State/Risk/Call briefings per auto delivery, where the Call line is "the go-ahead the orchestrator takes itself". Output with no reader.
- The Done stage tells the same story four times: `outcome.md`, an EM-to-CTO report, a Done briefing, and a summary stamped into the intent file.
- Twelve Announce mandates, three of which announce the skill's own name, which the harness already displays.
- The tier system, the one lever meant to make small work cheap, changes none of this: S vs L is 52 vs 61 steps, and 0 percent difference in gates, required files, ledger lines, and human interruptions. The tier stamp is also unverifiable (no gate or doctor check reads it).

### Ranked workflow fixes

| # | Fix | Saving |
|---|---|---|
| 1 | Split PLASTIC.md: an always-on core (~5.2k tokens) plus on-demand sections loaded by the skill that needs them | ~57k tokens per delivery, 31 percent of all overhead, zero behavior change |
| 2 | Delete the two report contracts and the Announce mandates; `outcome.md` stays the single truth, `scripts/agent-report` derives the rest | 2,000-2,500 output tokens per delivery, the largest single cut |
| 3 | Make tiers real: S must cut gates, files, and asks, not only agent boots; enforce the tier stamp in the gate-check so it becomes auditable | small work stops paying large-work overhead |
| 4 | Merge and delete skills: 6 merges (continue chain, install family, brainstorm+grill, curate+index, savepoint+locking, planning trims) and 6 deletions remove 47 percent of skill bytes with no capability lost | ~103KB of instruction |
| 5 | Fix the PreCompact savepoint hook: it currently orders a manual 5-step procedure referencing template sections that no longer exist; one call to the existing rebuild function replaces it | a wasted wrong turn on every compaction |
| 6 | Drop the mandatory full-board paste on continue when the hook systemMessage path is available | 600-1,200 tokens per continue |

The instruction surface splits roughly 34 percent load-bearing (exact CLI surfaces, filesystem schema, ordering constraints learned from real failures, determinism contracts) and 66 percent the system explaining itself to itself (rule archaeology, narration mandates, repeated restatements). Cut the second class only.

---

## 5. Loops engineering

The finding that explains most of the instruction bloat: **every gate in Plastic is a refusal, and every advance is prose.** Hooks say no; nothing in the system ever says "the next step is X". So the entire sequence must live in the model's context, which is why PLASTIC.md is 53KB and the auto skill is 24KB, and why both are re-read by every background agent.

The outer loop (Build, Observe, Repeat) has zero hooks, zero exit codes, and zero persisted state; `## Insights` is declared its feed and nothing reads it programmatically. It is documentation, not a mechanism. The inner lifecycle is real and gated, but its advance logic is 100 percent model-driven.

The fix is one script: **`scripts/next-step <intent-dir>`**, emitting `{stage, next_action, required_artifact, blocking_gate, dispatch_role, model}`. Every input it needs already exists in code (`derive_stage` and `missing_for_stage` in `bridge.rb`). With it, about 15 prose judgment steps become lookups, the orchestrator loop becomes "call next-step, dispatch, repeat", and the PLASTIC.md split becomes safe because the sequence no longer has to live in context. This is the same move the system already made once with `end-intent`, which collapsed a multi-step prose tail into one call, and the two skills that are already mostly script (intent-locking, intent-ending) are the shortest in the tree. Codifying shrinks prompt.

Companion moves, in order of value: `board-intent` (activation + lock + arm + discovery in one call with typed exits), `dispatch-specialist --role` (replaces 35 lines of dispatch prose), a reviewer receipt file plus doctor check (makes the never-cut reviewer verifiable), making the code gate mode-independent (today guided mode has no code-before-plan enforcement at all: one line in `bridge.rb`), and one merged PreToolUse dispatcher (about 130 fewer processes per trivial delivery).

Worst stall points to remove while at it: the mandatory stale-lock question blocks routine crash recovery (auto fail-open is already the recorded policy); exit 6 from `end-intent` forces a full tail re-run; the two per-task review loops are unbounded.

---

## 6. Graph engineering

The graph is correct (zero dangling references, zero validator violations across 458 intents) and essentially unread:

| Cost side | Value side |
|---|---|
| 3,675 lines of maintenance code | ~45 lines of consuming code |
| `## Links` = 188,549 bytes, 10 percent of every intent file | read by nothing except its own validator |
| 2,493 lines of graph tests (8.9 percent of the suite) | one dashboard label and one one-bit check in auto mode |

The topology tells the same story: median degree 2, meaning the typical intent is one parent and one child. It is a linked list wearing a graph's clothes; the meaning currently lives in the folgezettel IDs, not the edges. QMD flat search substituted for traversal, which is why the graph atrophied.

What to build, in priority order:

| # | Capability | Size | Payoff |
|---|---|---|---|
| 1 | **Context routing**: breadth-first walk, depth 2, from an intent's sources and chain; rank by hop, tier, recency; inject only the `## Outcome` and `## Insights` slices of the neighborhood into the working agent | ~150 LOC | Replaces three flat search hits with a provenance-known neighborhood; saves 3-8k tokens per intent; stops agents re-deriving decisions the parent intent already made. This is the biggest quality win in the whole review |
| 2 | Duplicate detection at creation (the candidate set is already computed in `link_suggestions.rb`) | ~80 LOC | Enforces what is currently an unenforced prompt instruction |
| 3 | `plastic-related <id>` query verb | ~40 LOC | Makes 3,600 lines of maintenance finally queryable by a human |
| 4 | Staleness and supersede detection (needs a `supersedes` edge type; `chain` currently conflates continuation with mere relation) | ~120 LOC | Catches late rulings against completed intents mechanically |

Two cheap schema fixes regardless: make edge weight machine-readable (`sources: [{id, w}]`; the high/medium/low rating already exists as prose) and add an acyclicity check to the validator (~10 lines; the store already contains one back edge that nothing detects).

Do **not** build dependency scheduling: the data does not exist. `sources` means "born from", not "blocked by", and only 19 edges connect two future intents. Topologically sorting this graph orders history, not work.

And retire the `## Links` body section: it is a rendering cache, recomputable from frontmatter, costing about 47k tokens store-wide. Generate it on demand for Obsidian users instead of storing it in every file.

---

## 7. Codify vs agent: the Jarvis split

The right split, confirmed by both analysis agents independently: **code decides and executes everything deterministic; the agent judges, designs, and writes.** Plastic already proves this works in miniature: its two most-scripted skills are its shortest, and its one deterministic report generator outperforms the mandated model-written reports.

Move to code (the framework):

| Behavior | Today | Target |
|---|---|---|
| Stage advance decision | prose across 3 skills | `next-step` (section 5) |
| Boarding (activate + lock + arm + discovery) | 4 prose steps + two 300-char inline Ruby one-liners the agent must retype | `board-intent` |
| Bridge arm | a 640-character `ruby -e` pasted in 3 skills | `plastic-lock arm` (the CLI already has 8 sibling verbs) |
| Store commits | `git add . && git commit` retyped in 11 skill locations; `git add .` in a parallel store is the known sweep-up bug | `store-commit --paths` |
| Terminal close | two skills hand-write the 6-step close, bypassing `end-intent` (live drift, the exact bug class `end-intent` was built to fix) | route everything through `end-intent` |
| Reciprocal link edits | hand-edited on both sides although `link-suggest --record` exists | use the script |
| Version bump + changelog cut | hand-edited, then a guard checks agreement after the fact | `bump-version` makes the guard redundant instead of remedial |
| Doctor fixes | a manual operations table in prose | `doctor --fix` (the JSON already emits `fixable: true` with hints) |
| Intent activation move | no script exists; `end-intent` owns the opposite move | `activate-intent` |
| Frontmatter scans | raw bash loops pasted in 2 skills that break on any `---` in a body | `list-intents --json` |

Keep with the agent (Jarvis): brainstorming, grilling, speccing, planning judgment, code writing, review judgment, the humanizer, and the continuing router. These are the judgment work, and no reason was found to codify any of them.

The Jarvis effect of this split is direct: when the framework can answer "what happens next" and "do this mechanical thing" by itself, the instruction files stop teaching procedure and shrink to conventions plus judgment guidance. Minimum instructions, maximum effect follows from the architecture rather than from writing shorter prose.

Also worth deleting outright: three dead migration scripts (~660 lines, zero references), the canonical gate fragment that ships but is read by zero skills while three skills inline diverged copies, and the ~95KB of eval JSON currently installed to every user with no runtime consumer (18 percent of installed skill size).

---

## 8. Reliability: the concurrency findings

These matter more than speed. No `flock` exists anywhere in `scripts/`; the only real mutual exclusion is `O_EXCL` at lock creation; every later mutation is unsynchronized read-modify-write; and there are zero concurrency tests in a 128-file suite.

Critical, in fix order:

1. **The session-start hook passes the wrong store path** (`$HOME/.plastic` instead of `~/.plastic/store`), so a malformed bridge shape coexists in /tmp right now, under which the active-intent check reads a nonexistent INDEX and other sessions may purge a live bridge. One-line fix.
2. **SessionStart wipes an armed bridge on every resume.** The hook fires on startup, resume, clear, and compact, and unconditionally writes a virgin bridge (auto off, worktree nil) over the same key. This is the reproducible mechanism behind both documented bugs: the worktree pointer is not raced away, it is reset to null by a hook. Guard: never derive over an armed bridge.
3. **Atomic lock writes.** `Lock.write` is a plain `File.write`; a torn read makes the true owner fail its own ownership check, after which repair deletes and re-acquires: two owners. Use tmp+rename, then add `flock` around the read-modify-write sites (delegate registration can currently drop entries, which then denies that subagent every write).
4. **Move `build.auto` out of /tmp into the intent directory.** It is the one piece of authoritative state living in the cache: a /tmp wipe silently disables the pre-plan code gate with no warning. This change makes "the bridge is only a cache" true as written, and fixes `disarm_auto` trusting the cache over the lock file (today the release result is discarded, orphaning locks, and with two bridges it can remove a sibling's worktree).
5. Then the medium tier: heartbeats fire only on write-path hooks, so 30 minutes of reading or a long test run expires the lease under a live owner (touch on read-path or lengthen the lease); the savepoint rebuild erases takeover audit records (append-only them); the undocumented `plastic-lock release --session <old>` is the only recovery for the bg-resume case and should be in the usage text; add the first real concurrency test.

The fail-open philosophy is right and matches the recorded ruling. The one violation of its spirit: failing open on your own state is correct, failing open into deleting another session's state (the purge path) is not.

---

## 9. Market landscape and trends

### The field (verified 2026-08-02)

| System | Unit of work | Traction | Standout | Weakness |
|---|---|---|---|---|
| Superpowers (obra) | skill | 264.9k stars, 137k+ installs | methodology as skills; marketplace distribution | no persistent work store, no cross-session unit |
| Spec Kit (GitHub) | spec doc | 125k stars | institutional distribution (MS Learn, VS Code) | verbose, no state between specs, no community |
| GSD | task in phases | 64.8k, ARCHIVED after token rug-pull; fork at 7.6k | named the enemy ("context rot") | governance collapse, the category's cautionary tale |
| BMAD-METHOD | agile story | 51.4k, Discord 15k, YouTube 20k | full simulated agile team | heavy for solo work, no monetization |
| OpenSpec (YC) | spec delta | ~28k | models change-as-diff | change-shaped, no ideation |
| Taskmaster | task in tasks.json | 27.9k, 150k+ downloads | dependency-aware "what next", MCP-native | JSON blob, commercial lane reserved |
| beads (Yegge) | node in dependency DAG | 25.8k, 23.7k npm/mo | serious long-horizon agent memory | dependencies, not meaning |
| Backlog.md | task as md file | 6.3k, 24.1k npm/mo | TUI board + web UI on plain files | no lifecycle depth. Closest to Plastic on file format |
| Agent OS (Casel) | spec + standards | 5.2k | standards-first; best business (paid membership) | small surface |
| Kiro (AWS) | spec (EARS) | GA, paid tiers | only IDE-native SDD | 16 acceptance criteria for a small bug fix |
| Conductor | workspace | $22M raised | best parallel-worktree UX | no ticket, no lifecycle |
| Plastic | **intent (a desire)** | 9 stars | graph store + deterministic gates + advisor + outcome record | traction, ceremony, single-user |

Commercial layer above the open tools: Devin (session + playbook, ARR $73M to $492M in 11 months), Linear for Agents (the cleanest object model: a typed AgentSession beside the issue), Amp (argues the thread should replace the ticket), Augment Cosmos (the ticket, enterprise-only), Factory (spec agreement gates edits). Notable small neighbors: J-Tech intent-system (76 stars, a deterministic non-LLM referee CLI: the same instinct as Plastic's hooks), memex (Zettelkasten for agents, 139 stars), kanban-md (atomic claim with expiring leases, a better lock design than Plastic's on one axis).

### Trends that matter

1. **"Intent-driven development" is claimed as a term, unclaimed as an artifact.** Sean Grove's "The New Code" (2025) is the origin citation; intent-driven.dev (Hari Krishnan) owns the term as a category umbrella; Microsoft Research named the "intent gap" (arXiv:2603.17150); SpecStory sells "intent is the new source code" as a tagline. But only four repos ship intent as a typed durable artifact, the largest at 495 stars. You are not early on the term. You are genuinely early on the implementation. Do not fight for the word; be the reference implementation people point at.
2. **The evidence is turning against heavy specs.** ETH Zurich measured that context files do not generally improve task success while raising cost 20 percent (arXiv:2602.11988); Thoughtworks' Böckeler compares spec-as-source to Model-Driven Development's failure by overhead; the Macedo taxonomy (arXiv:2606.04967) finds no framework excels across all dimensions and flags "absent benchmarks for complete processes". This cuts against Plastic's ceremony and for Plastic's deterministic-gates-plus-thin-prose direction. The benchmark gap is the single largest unclaimed credibility play in the category.
3. **Distribution consolidated into marketplaces.** Superpowers went from a blog post to 137k+ installs on one marketplace listing. Skills (SKILL.md) quietly won the format war and is read by every major harness.
4. **The unit-of-work middle is empty.** Capital went to the PR (CodeRabbit, Qodo, Graphite) and the session (Devin, Conductor, Factory). A durable, human-legible work item that an agent owns from idea to outcome has one enterprise implementation and no open-source leader. That is Plastic's lane.

### Ecosystem effect, honestly stated

If Plastic executes, its effect on the ecosystem is to legitimize the intent (not the spec, not the task, not the session) as the unit of agent work, and to prove that process enforcement belongs in deterministic hooks rather than prompts. Those two ideas are already being groped toward by Linear (AgentSession), Augment (ticket), and intent-system (referee CLI); an open reference implementation with a benchmark would give the pattern a name and a home. The realistic failure mode is equally clear: a deep system with a slow surface at 9 stars stays a personal tool. The difference between the two outcomes is distribution and proof, not more features.

---

## 10. Go-to-market playbook (ranked)

1. **Plugin marketplaces first.** Claude Code first-party marketplace, the community mirror, Cursor plugins, awesome-copilot. The only channel in the data with a step-function effect. Everything else multiplies distribution you do not yet have.
2. **Ship the benchmark nobody has.** Plastic vs Spec Kit vs BMAD vs bare Claude Code, same task set, published data and method. It converts your heaviness from a taste argument into a testable claim, and it is the fastest route to a Willison-tier link (his single paragraph is the identifiable pivot in the Superpowers growth curve).
3. **Earn one high-trust endorsement.** Targets in order of fit: Geoffrey Huntley (the Ralph thesis, progress lives in files and git, is Plastic's thesis), Simon Willison, Addy Osmani, Birgitta Böckeler as the skeptic to convert.
4. **Name the enemy and attach a number.** "Context rot" is taken. Plastic's natural enemy: the idea that dies in a chat log, or work that ships with no record of why. Pick one, measure it, put the number in every title.
5. **One long honest build-log post** with a real project, real failures, and real transcripts. This is what feeds item 3 and a Hacker News thread; launch announcements do not.
6. **YouTube walkthrough with the number in the title.** Compounding channel; both BMAD and Agent OS were built on it; expect nothing for two quarters; third-party videos did Taskmaster's growth for free once the number existed.
7. **LinkedIn as curriculum, not feed.** Your influence there reaches engineering managers and CTOs, the audience for the governance story: sell the outcome record and audit trail (`outcome.md`, the decision graph, the gates) as traceability for agent work. Hands-on developers are not there; they are in r/ClaudeCode, r/ChatGPTCoding, and YouTube. The proven LinkedIn tactic in this exact category is a LinkedIn Learning style course, not posts.
8. **Fix governance before you need it.** Move the repo to an org, add a second maintainer, publish a short governance note. GSD converted 65k stars into a 7.6k restart because trust collapsed. Costs an afternoon; insures everything above.

Skip: Discord (retention, not acquisition), podcasts (after ~30k stars), newsletters, paid ads.

**Monetization, decide now:** the Casel shape fits best (free open tool, paid membership/workshops/courses for teams adopting AI agents), matching your LinkedIn position and the enterprise governance angle. The alternatives are Commons Clause plus SaaS (Taskmaster) or MIT plus enterprise services (Superpowers). The one shape that killed a project in this field was a token.

---

## 11. Language: Ruby, Go, or Crystal

Stay on Ruby. The measured case:

| Runtime | Startup per process |
|---|---|
| Ruby 4.0.3 | 55ms |
| Ruby with `--disable-gems` | 16ms |
| Node 22 | 45ms |
| Compiled binary (floor for Go/Crystal) | 5ms |

A compiled rewrite buys about 11ms per spawn over `--disable-gems` Ruby, roughly 66ms per edit, while the architectural fixes in section 3 are worth about 600ms per edit. The workload is I/O and subprocess-bound (git shell-outs, file parsing, the language-invariant 526ms `qmd` probe), not CPU-bound. The rewrite would cost about 20,500 lines and discard a green 6,406-assertion suite, which is the main protection against exactly the concurrency defects in section 8 that a rewrite would likely reintroduce. Ruby is also your language, per your own recorded stance that Go needs a strong reason: these numbers do not supply one.

Distribution stays npm (the Node shim is 58 lines and only dispatches); a single binary would add a four-platform build matrix to every release for no user-visible gain.

Revisit a compiled core only if, after the section 3 fixes land and are re-measured, hook count grows enough that the 16ms floor times N dominates. Decide then, with numbers.

---

## 12. Master action plan

Sequenced so each batch is independently shippable and the risky work rides on a faster, safer base.

| Batch | Contents | Outcome |
|---|---|---|
| 1. Snappy (days) | qmd cache; delete bash shims; `--disable-gems`; stop loading doctor at boot; bridge key index | Write/Edit under 250ms, Read near 50ms, prompt near 200ms. Users feel this immediately |
| 2. Safe (days) | store-path one-liner; SessionStart derive guard; atomic lock write + flock; move `build.auto` into the intent dir; first concurrency test | The two most-reported bug families become impossible rather than worked around |
| 3. Lean (week) | PLASTIC.md split; delete report contracts and announce mandates; skill merges and deletions; PreCompact fix; retire `## Links` bodies | ~40 percent of process overhead and most ceremony gone without touching a gate |
| 4. Codified (week) | `next-step`, `board-intent`, `plastic-lock arm`, `store-commit`, `doctor --fix`, `activate-intent`, `list-intents`; route all closes through `end-intent`; real tiers (S cuts gates and files, stamp enforced) | The loop becomes deterministic; skills shrink to conventions plus judgment; the Jarvis split is real |
| 5. Remembering (week) | graph context routing; duplicate detection; `plastic-related`; machine-readable edge weights; acyclicity check | The graph starts paying rent: agents inherit decisions instead of re-deriving them |
| 6. Seen (ongoing) | marketplace listings; the benchmark; build-log post; org + second maintainer; enemy-plus-number framing; LinkedIn governance track | Distribution and proof. Target: Agent OS territory (~5k stars) within two quarters of batch 6 starting |

Batches 1 and 2 before anything public: the first impression a marketplace user gets must be the snappy version, and the reliability fixes must precede any multi-user attention.

---

## Appendix: sources and method

Full agent reports (code/runtime review with all measurements; workflow/instruction review with all counts; market research with ~40 primary source links including arXiv:2602.11988, arXiv:2603.17150, arXiv:2606.04967, the Böckeler Thoughtworks series, and per-repo verification dated 2026-08-02) are preserved in the review job archive. Key local references: hook wiring `hooks/hooks.json:32-147`; retrieval probe `scripts/hook-retrieval-gate:95` and `scripts/lib/qmd_sync.rb:144-150`; injection `scripts/hook-session-start:123-126`; god module `scripts/lib/bridge.rb` (1,620 LOC, 71 methods); lock model `scripts/lib/lock.rb`; stage derivation `bridge.rb:456-517`; tier invariant `skills/auto/references/tiers.md:57-63`; graph write sites vs the single consumer `scripts/dashboard.rb:264-333`.
