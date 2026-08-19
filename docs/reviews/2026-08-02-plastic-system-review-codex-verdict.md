# Codex adversarial verdict on the Plastic system review

Date: 2026-08-02  
Reviewed report: `2026-08-02-plastic-system-review.md`  
Code reviewed: Plastic v1.8.0 at `e6c795b56a01da6c5e8381516a233a9e05d5f606`

## Bottom line

Claude's report is a strong source of hypotheses and a weak decision surface.

Its central engineering direction is right:

- keep Ruby for now;
- remove repeated process startup and broad always-on context before considering a rewrite;
- move deterministic lifecycle mechanics from prose into code;
- make the graph produce working context, not only validated links;
- publish a real benchmark before making performance or market claims.

But the report should not be accepted as verified in its current form. Several high-confidence claims are false, several measurements cannot be reproduced from the archived material, the market section contains material factual errors, and the review does not cover the harnesses or the public documentation deeply enough to satisfy the original prompt.

My verdict by dimension:

| Dimension | Grade | Verdict |
|---|---:|---|
| Architectural direction | B+ | Mostly right, especially the Ruby and deterministic-core conclusions |
| Local code evidence | B- | Good code reading, but some absolute claims are false and several scopes are mixed |
| Performance evidence | C+ | Plausible bottlenecks, no reproducible benchmark bundle, measured on a non-project Ruby runtime |
| Workflow analysis | C+ | Real ceremony exists, but the token and step multipliers are modeled as if measured |
| Reliability analysis | C+ | Important lock and SessionStart risks found, but the proposed path fix is incomplete and concurrency claims are overstated |
| Graph analysis | C+ | Under-consumption is real; deletion and schema recommendations ignore human and external consumers |
| Harness coverage | D | Claude, Codex, and Hermes have materially different contracts; the report mostly treats Plastic as one harness |
| Market research | D+ | Useful field map, but multiple stale, false, unsupported, or causal claims |
| Go-to-market advice | C+ | Benchmark-first is strong; most channel causality is hypothesis, not evidence |
| Overall | C+ | Keep as an issue-discovery backlog, not as the roadmap |

## What I checked

This Codex pass was performed outside Plastic's lifecycle at the owner's request.

I checked:

- the synthesis report and all three archived agent reports;
- source and installed v1.8.0 surfaces;
- hooks, bridge, lock, worktree, installer, doctor, graph, dashboard, skills, agents, and harness documentation;
- Claude, Codex, and Hermes adapter differences;
- the full Minitest suite;
- current primary sources for the main ecosystem and research claims.

Current local observations:

| Check | Result |
|---|---|
| Source and installed `PLASTIC.md` | Byte-identical, 53,558 bytes |
| Installed shared core | v1.8.0 |
| Installed Claude integration | v1.8.0 |
| Installed Codex integration | v1.8.0 |
| Claude core doctor | 23 pass, 0 warn, 0 fail |
| Codex full doctor | 33 pass, 6 warn, 0 fail |
| Full suite, project Ruby | 1,837 runs, 6,398 assertions, 0 failures, 0 errors, 0 skips |
| Full-suite runtime, project Ruby | 221.63 seconds on the project's configured Ruby 3.3.5 |
| Full suite, Claude's Ruby | 1,837 runs, 6,406 assertions, 0 failures, 0 errors, 0 skips in 163.23 seconds on Ruby 4.0.3 |

The green-run claim is confirmed. The report's 6,406-assertion result reproduced under its Ruby 4.0.3 runtime, within 2.5 seconds of the archived elapsed time. The same unchanged code produced 6,398 assertions and took 221.63 seconds under the project's configured Ruby 3.3.5. That is not a product failure. It shows why exact measurements need commands, environment, payloads, raw samples, and a pinned commit.

The repository pins Ruby 3.3 in `mise.toml`. Claude benchmarked with a separately invoked Ruby 4.0.3. That is a useful experiment, but it is not the default project runtime and cannot be presented as the machine's normal Plastic cost without qualification. QMD is also absent from the current shell, so the reported 526 ms QMD probe cannot be reproduced now.

## Findings from the original verdict

### 1. "The mechanism layer is good; the instruction layer is the problem"

Verdict: directionally correct, numerically unsupported.

The mechanism layer is substantial and the instruction surface does repeat decisions. However, "two thirds is redundant" comes from an undocumented manual classification. The archive does not include a file-by-file classification, rubric application, or token source from which another reviewer could reproduce 34 percent load-bearing versus 66 percent redundant.

The correct decision is to measure instruction value per workflow, not delete everything classified as narration.

### 2. "Speed is architecture, not language"

Verdict: confirmed as the current decision, with weaker numerical confidence than reported.

The code confirms the main mechanisms:

- `scripts/hook-retrieval-gate:87-106` calls the QMD freshness probe whenever QMD is detected;
- `scripts/lib/qmd_sync.rb:144-150` shells out to `qmd status`;
- several hook launchers parse the same stdin JSON in separate Ruby processes;
- `scripts/hook-session-start:12` loads all of `doctor.rb`;
- `Bridge.discover_bridge` scans and parses `/tmp/plastic-*.json` candidates.

The project Ruby 3.3.5 startup measured about 88.8 ms normally and 26.0 ms with `--disable-gems` in a 20-spawn sample. Ruby 4.0.3 measured about 68.8 ms and 15.5 ms respectively. The relative win is real. The exact promise of Write/Edit below 250 ms and Read near 50 ms is not yet a product result.

Stay on Ruby. Re-measure the actual supported path before promising target latency.

### 3. "The Judo principle is inverted for small work"

Verdict: plausible and important, but the 52-step and 78x figures are a workflow model.

The archive contains a counted idealized path, not an observed trace with real API input tokens, cached tokens, output tokens, elapsed time, and agent invocations. It also undervalues the principal benefit of Tier S: fewer agent boots and shallower artifacts, even when the file schema remains stable.

The product question should be measured directly:

> For the same accepted change, how much elapsed time, cost, human attention, recovery work, and defect escape does Plastic add or remove?

Step count alone cannot answer that.

### 4. "The intent graph is written but not read"

Verdict: directionally correct, overstated as an absolute.

The graph has little runtime consumption compared with its maintenance surface. A context-routing consumer is worth prototyping. But the report ignores non-code consumers: humans, Obsidian, wikilink navigation, doctor diagnostics, and provenance inspection.

The graph metrics also mix scopes. The current store family has 458 intents. The Plastic project store alone has 293 intents and 580 frontmatter source/chain entries. The report presents 458 intents, 580 edges, and roughly 188 KB of links as one population. Those are not one population.

### 5. "The market window is open"

Verdict: opportunity exists, empty-category and uniqueness claims do not.

Plastic has a defensible combination: intent-to-outcome lifecycle, human-readable graph, deterministic enforcement, resumability, and a permanent outcome record. That combination should be proved. The surrounding market is crowded and converging quickly.

## Local claim audit

| Original claim | Verdict | Evidence and correction |
|---|---|---|
| 1,837 test runs and a green suite | Confirmed | Reproduced 1,837 runs with no failures |
| 6,406 assertions in 165.7 seconds | Reproduced with runtime qualification | Ruby 4.0.3 produced 6,406 assertions in 163.23 seconds; project Ruby 3.3.5 produced 6,398 in 221.63 seconds |
| 970 ms to 251 ms for three gates | Direction confirmed, exact values not reproduced | A fresh three-gate sample was about 882 ms through shell launchers and 175 ms through direct `ruby --disable-gems`; no archived payload, raw sample, or variance is available |
| QMD freshness runs on each retrieval event when QMD exists | Confirmed | `hook-retrieval-gate` calls `QmdSync.fresh?`; that calls `qmd status` |
| The hot hook path has redundant JSON parsing and Ruby startup | Confirmed | Seven launchers contain `JSON.parse(STDIN.read)` and several start multiple Ruby processes |
| There are 18 bash shims | False and over-broad | `hooks/` contains 17 shell files plus `hooks.json`; several shell files carry behavior rather than acting only as shims |
| PLASTIC.md is 55,558 bytes | Not reproduced | Source and installed file are both 53,558 bytes; a larger hook payload may have been conflated with the file |
| 66 percent of shipped instruction is redundant | Unsupported precision | No reproducible classification artifact is archived |
| A medium delivery costs 78x a bare agent | Unsupported as a measurement | This is a modeled context bill with assumed sessions, not an observed usage trace |
| Every Plastic gate is a refusal and nothing says what comes next | False as stated | `Bridge::NEXT_HINTS` and `gate_narration` emit `Next:` instructions; the weaker claim, no standalone lifecycle driver exists, is correct |
| The fallback report proves agent-authored completion reports are unnecessary | False | `scripts/agent-report` explicitly calls itself an approximation and cannot recover tests run, deviations, blockers, action rationale, or unpersisted insights |
| The graph has zero validator violations across 458 intents | False for current state | The current full doctor reports an unresolved cross-store ref and related projection warnings for global intent 27 |
| `## Links` is read by nothing except its validator | False as a product claim | It is also the human-readable and Obsidian-facing graph projection, even if runtime code barely consumes it |
| No `flock` exists anywhere under `scripts/` | False | `scripts/write-config:63-64` takes an exclusive `flock` |
| There are zero concurrency tests | False | `test/write_config_test.rb:114-134` runs concurrent writers; end-intent has a TOCTOU test. The narrower finding, no real lock read-modify-write race test, is valid |
| SessionStart records the wrong store shape and should pass `~/.plastic/store` | Defect confirmed; proposed fix incomplete | `hook-session-start` passes `~/.plastic` into `Bridge.derive(store:)`, while `Bridge.intent_active?` expects the store directory and finds its INDEX in the parent. But changing only the caller argument would make `hook-session-start` build `store/store/<intent>`. Separate Plastic root from intent-store path, or normalize both constructions together |
| SessionStart can overwrite armed bridge state | Partly confirmed | `Bridge.derive` writes `auto: false` and a null worktree. Overwrite requires the same stable session key, exactly one matching active global intent, and the event path described. It needs a reproduction test before being called the cause of two bug families |
| The tracked create gate works through the plugin's generic hook dispatcher | False; omitted by the report | Git records `hooks/create-gate` as mode `100644`, while executable `hooks/run-hook` invokes it directly. `hooks/run-hook create-gate` exits with permission denied before Ruby runs. The standalone installer masks this by copying individual hooks and applying mode `0755`; the source plugin path remains broken |
| `Lock.write` is non-atomic and delegate mutations are unlocked RMW | Confirmed | `scripts/lib/lock.rb:204-249,295-297` reads, mutates, and writes in place without lock or rename |
| `build.auto` is authoritative state in `/tmp` | Confirmed | `code_gate_decision` returns unless `build["auto"] == true`; repair derives mode from the prior bridge |
| Guided mode lacks the pre-How code gate | Confirmed | `Bridge.code_gate_decision:1104` is conditional on auto mode |
| Lock and worktree gates relax for positively confirmed solo work | Confirmed, intentional | This is documented policy, not an undisclosed gate failure |
| The PreCompact savepoint prompt references retired Build/Observe sections | Confirmed | `hooks/savepoint` still instructs manual writes to retired shapes |
| `plastic-lock release --session` is undocumented | False as stated | `scripts/plastic-lock` includes `--session` in its usage line and parser. The specific background-resume recovery procedure may still need documentation |
| A Go or Crystal rewrite is not justified now | Confirmed | Process topology, external commands, and I/O dominate before language runtime does |

## Another top-priority finding: public documentation contradicts the implementation

Claude reviewed worktrees, locks, maintenance, and documentation, but did not surface this concrete cross-surface defect.

| Surface | Stale claim | Current truth |
|---|---|---|
| `AGENTS.md:102` | A paired store worktree exists at `~/.plastic/.worktrees/...` | Intent 178 retired the store worktree; only the code worktree remains |
| `docs/architecture.md:197-200` | Bridge holds code and store worktree paths; two worktrees are provisioned | `scripts/lib/worktree.rb:21-25,65-80,134-170` provisions one code worktree |
| `docs/architecture.md:215` | Terminal content becomes writable under a future maintenance lock enforced by intent 112 | Intent 112's lock was abandoned; maintenance detects the delivery lock and acquires no second lock |
| `docs/internals.md:774-775` | Code and store worktrees both exist | Store worktree is retired |
| `scripts/restore-intent-v1:145-146` | Operator must confirm a maintenance lock is held | No maintenance lock exists in the current doctrine |
| `README.md:152` | Compatibility sentence says "Native installers for Claude (Codex, Hermes..." | Sentence is malformed and obscures the different support levels |

This drift is more urgent than deleting migration scripts or changing graph schema. It directly misleads contributors and operators about isolation and ownership.

## Harness verdict

The original prompt asked for harnesses thoroughly. The report does not deliver that.

| Harness | Actual current shape | What the review missed |
|---|---|---|
| Claude Code | Interactive adapter is documented as Tier B. Create can be vetoed before write, but some artifact validation is a post-write signal | Plastic's enforcement is not uniformly a pre-write block |
| Codex | Skills install to `~/.agents`; conventions and hooks install under `~/.codex`; eight role TOMLs install because both advisors are deliberately excluded | Tier A is conditional on hook trust, supported version, and a best-effort `apply_patch` envelope parser that fails open on unknown syntax |
| Hermes | Installer copies skills and agent files and writes version/manifest state | No Hermes hook registration, standing-convention injection, skill invocation prefix, or worked adapter contract exists. It is packaging support, not lifecycle parity |

The current Codex install contains hook registrations and trusted hashes, but the shell used for this audit has no `codex` executable on `PATH`. Doctor therefore cannot confirm the minimum hook version. This is not proof the active Codex product lacks support; it is proof the report should distinguish installed files, documented capability, and live verified capability.

The adapter document itself admits that the Codex patch-envelope grammar is not primary-sourced and fails open. That does not fit its own Tier A definition that gates cannot be silently bypassed. Tier naming should be based on tested behavior, not intended wiring.

Two additional harness findings materially change the review:

- The 78x token model assumes seven sessions each receive the full `PLASTIC.md`. Plastic's own adapter documentation says Claude's `SessionStart` is top-level only and that subagents fire the unwired `SubagentStart` event. A spawn preamble gives subagents live intent state, but it is not a second full `PLASTIC.md` injection. The report's largest token multiplier conflicts with the documented adapter behavior and must be measured from real API usage.
- The source skills are copied byte-for-byte into both Claude and Codex installations. At least 76 source lines still contain `CLAUDE`, `~/.claude`, or Claude-style `/plastic-*` references. Concrete failures include `${CLAUDE_PLUGIN_ROOT}` in intent creation and outcome-template instructions, plus a dashboard template path under `~/.claude/skills`. Codex packaging exists, but the installed instruction content is not yet adapter-clean. Current tests check selected names and files, not portability of every installed instruction.

Hermes is weaker still: it has an installer target but no verified runtime adapter. Therefore the product currently has one mature adapter, one partially portable adapter, and one packaging target—not three equivalent harness integrations.

## Workflow and narration: what to cut and what to keep

Claude is right that Plastic talks too much. The proposed deletion boundary is wrong.

### Keep, but compress

- The specialist completion report. It carries deviations, blockers, tests, rationale, and insights that filesystem inspection cannot reconstruct.
- `outcome.md` as the durable delivery truth.
- A short human boundary update when risk, a decision, or material progress exists.
- The independent final review.

### Remove or change

- Do not require a human-facing State/Risk/Call message at every autonomous boundary when there is no new risk or decision.
- Remove skill-name announcements and repeated handoff prose.
- Replace duplicated commands and exit-code explanations with deterministic CLI output.
- Make the agent report compact and machine-readable, then render a human summary only when needed.
- Treat `scripts/agent-report` as a degraded fallback, which is exactly how its source describes itself.

The skill-deletion advice also needs a named, capability-level diff. The report says the humanizer is judgment work to keep while proposing six unspecified skill deletions and claiming no capability loss. Those statements are not directly contradictory only if the deletion set is published; without that set, the recommendation is not auditable.

The correct rule is one truth per audience:

| Audience | Truth surface |
|---|---|
| Lifecycle machine | Filesystem state plus typed CLI output |
| Orchestrator | Compact specialist receipt with deviations, tests, blockers, insights |
| Human | Exception-driven briefing plus final outcome |
| Future reader | `outcome.md` and durable insights |

## Tiers: do not buy speed by destroying the schema

The report recommends that Tier S cut gates and lifecycle files. That is a major architecture change, not a workflow trim. Plastic's fixed schema is what makes state derivable and recovery deterministic.

First make Tier S fast inside the invariant:

- one thinker boot for Why and How;
- short artifacts;
- one consolidated action;
- one executor;
- one independent reviewer;
- one process per hook event;
- bundled deterministic create, board, advance, and close verbs.

Only introduce a different micro-intent schema if a benchmark shows this is still too expensive and the alternative has equally clear recovery semantics. Do not silently make S, M, and L mean different state machines.

## Graph engineering: build the consumer before changing the schema

The proposed context router is promising. The remaining recommendations jump ahead of evidence.

1. Prototype read-only context routing over the existing arrays.
2. Load `sources` strongly and traverse `chain` lightly, matching Plastic's existing semantic contract.
3. Measure retrieval precision, tokens, decision reuse, and stale-context rate.
4. Decide and document whether `sources` must be acyclic. The live Plastic project has a sources-only cycle: `22c -> 14 -> 13 -> 19a -> 22c`, and the validator does not reject it. `chain` is explicitly allowed to carry relational cycles.
5. Keep `## Links` until the human and Obsidian replacement is proven.
6. Do not change arrays to `{id, w}` objects until every parser, validator, doctor check, script, skill, and external consumer has a migration plan.

The suggested 3-8k token saving, 80-line duplicate detector, 150-line router, and 10-line acyclicity check are estimates, not scoped implementation plans.

## Reliability: revised priority

The report found a real SessionStart shape defect but reduced it to an unsafe one-line fix. `hook-session-start` currently uses one `store_root` argument for two different concepts: the Plastic root used to find `projects.yml` and `PLASTIC.md`, and the actual intent-store directory expected by bridge consumers. Those concepts must be separated or normalized together.

The safer order is:

| Priority | Work | Reason |
|---:|---|---|
| 0 | Restore executable mode on `hooks/create-gate` and add a plugin-dispatch smoke test | The plugin's generic create-gate path currently fails before enforcement code runs; the standalone installer happens to repair the mode on copy |
| 1 | Separate Plastic-root and intent-store semantics in SessionStart; test bridge creation, active checks, purge, and project/global stores | Confirmed malformed bridge shape; avoids the proposed `store/store` regression |
| 2 | Guard SessionStart against clobbering an already armed bridge and reproduce each affected event path | The overwrite mechanism is plausible but conditional |
| 3 | Add lock concurrency tests, then atomic rename plus locking around owner-side RMW | Confirmed data-loss and torn-read class |
| 4 | Remove derived-key owner aliasing between genuinely separate sessionless processes | Two unknown sessions must not become one authority merely because store and intent match |
| 5 | Move authoritative mode state out of volatile cache or reconstruct it from durable state | Makes "bridge is only a cache" true |
| 6 | Make disarm verify the durable release result and target an explicit intent | Avoid orphaned or wrong-intent cleanup |
| 7 | Heartbeat long reads/tests or use a lease strategy that does not expire active work | Prevent false staleness |

Safety changes come before performance changes because concurrency defects can destroy or misattribute state, while hook latency only wastes time.

## Market and research corrections

The archived competitor report contains no source links, despite the synthesis saying roughly 40 primary links were preserved. This is a provenance failure on its own.

| Claim | Verdict | Correction |
|---|---|---|
| OpenSpec has about 28k stars | False | GitHub API reported about 63.5k, making it a first-tier comparator, not a distant one: [OpenSpec API](https://api.github.com/repos/Fission-AI/OpenSpec) |
| Spec Kit has no state between specs and no community | False | Official docs describe pause/resume behavior, 240+ contributors, extensions, presets, and community catalogs: [Spec Kit](https://github.github.com/spec-kit/index.html) |
| OpenSpec is change-shaped with no ideation | False | Current docs include `/opsx:explore` for uncertain ideas before a proposal: [OpenSpec docs](https://openspec.dev/docs) |
| GSD archived after a token rug-pull and governance collapse | Archive confirmed; causation unsupported | Archive and community continuation are facts. "Rug-pull" and causal claims require authoritative evidence, not community allegation |
| Devin grew from $73M to $492M ARR | Misleading | $73M was stated for standalone Devin; $492M is Cognition-wide run-rate revenue after Windsurf: [Cognition growth](https://cognition.com/blog/funding-growth-and-the-next-frontier-of-ai-coding-agents), [Cognition Series D](https://cognition.com/blog/series-d) |
| ETH research shows evidence against heavy specs | Unsupported inference | The paper studies repository context files, not full spec-driven workflows: [arXiv:2602.11988](https://arxiv.org/abs/2602.11988) |
| No framework covers every process dimension; complete-process benchmarks are missing | Supported | This is what the Macedo taxonomy actually reports: [arXiv:2606.04967](https://arxiv.org/abs/2606.04967) |
| Sean Grove originated intent-driven development | Unsupported | The essay is influential but does not establish origin; intent-driven programming predates it |
| Only four repos have a typed durable intent artifact | Unsupported | No inclusion rule, repo list, or census query is preserved |
| Skills won every major harness | Directionally plausible, absolute unsupported | Anthropic and OpenAI support the shared skill format, but universal support was not demonstrated |
| The unit-of-work middle is empty | False as an absolute | It is crowded but lacks a clear open-source intent-to-outcome leader |
| Marketplace, Willison, YouTube, LinkedIn, Discord, and podcast thresholds caused observed growth | Unsupported causality | Treat each channel claim as an experiment with tagged acquisition and activation metrics |

The benchmark-first recommendation survives this audit. It is the strongest go-to-market recommendation because the research explicitly identifies missing end-to-end process benchmarks.

## Product coverage the first report missed

| Surface | Coverage verdict |
|---|---|
| What/Why/How/Exec lifecycle | Covered well |
| Hook process topology | Covered well |
| Lock and bridge | Covered deeply, with important errors in final ranking |
| Graph | Covered deeply, but only as code economics |
| Dashboard | Mentioned, not evaluated as a product surface |
| Roadmaps and wave delivery | Essentially omitted |
| Project creation and store provisioning | Omitted |
| Install, update, repair, rollback, and uninstall semantics | Omitted |
| Three doctor scopes and harness-specific doctor behavior | Omitted |
| Release lanes and release guard | Omitted |
| Maintenance tools and `revisions.md` | Discussed indirectly, public drift missed |
| Tutorial and onboarding | Omitted beyond the 90-second recommendation |
| Feedback, humanizer, skill evaluation, and skill creation | Counted as instruction, not evaluated as features |
| Advisor | Praised, not evaluated for cost, availability, harness parity, or outcomes |
| QMD, Enola, and Serena | QMD treated mostly as latency; retrieval quality and optional-tool behavior not evaluated |
| Claude/Codex/Hermes parity | Inadequate |
| Team and company adoption | Single-user drawback named; collaboration, privacy, policy, RBAC, shared audit export, and admin surfaces not analyzed |
| Supply-chain and installer risk | Not analyzed |

Because these surfaces were not evaluated, the original report does not support the phrase "all features thoroughly."

## Revised architecture split: framework, agent, and human

The binary "code versus agent" split should be a three-part contract.

| Owner | Responsibilities |
|---|---|
| Framework | Observe filesystem truth, validate artifacts, arbitrate ownership, execute atomic state changes, expose typed status and next legal transitions |
| Agent | Interpret intent, research, choose tradeoffs, design, plan, implement, review, and explain deviations |
| Human | Set goals and constraints, rule on meaningful tradeoffs, authorize destructive or organizational changes, accept outcomes |

A `next-step` command should report the current state and legal transitions. It should not pretend to decide the semantically best next action. That distinction preserves Jarvis-like initiative without hiding judgment inside code.

## Revised action plan

### Batch 0: Truth before optimization

- Restore and test the create gate's executable mode.
- Fix SessionStart's root/store data model and protect armed bridges with regression coverage.
- Fix `AGENTS.md`, `docs/architecture.md`, `docs/internals.md`, and `restore-intent-v1` so they match the one-worktree, one-lock implementation.
- Publish an honest harness matrix: installed, documented, and live-verified capabilities per Claude, Codex, and Hermes.
- Make installed skills adapter-aware: remove Claude-only variables, paths, and invocation syntax from Codex output, then lint all installed instructions per harness.
- Remove or qualify false market and research claims in the original report.

### Batch 1: Reproducible safety and speed baseline

- Add a benchmark command to the repository.
- Pin commit, Ruby path/version, harness, QMD present/absent/fresh/stale, bridge count, hook payload, sample count, p50/p95, and raw results.
- Measure actual API tokens and elapsed time for S, M, and L reference tasks.
- Add process-level lock race tests before changing lock code.

### Batch 2: Safe and snappy mechanics

- Make lock mutations atomic and serialized.
- Fix sessionless authority aliasing and durable-mode recovery.
- Cache QMD freshness only when QMD is installed.
- Replace repeated launcher parsing with one Ruby dispatcher per event.
- Apply `--disable-gems` only to verified hot paths that need no gem activation.
- Re-measure before publishing latency targets.

### Batch 3: Codified loop

- Add typed `status` and legal-transition output first.
- Bundle board/arm/activate/discovery mechanics behind one command with typed exits.
- Add scoped store commits and deterministic activation.
- Keep semantic prioritization and review with the agent.
- Make human updates exception-driven.

### Batch 4: Graph that pays rent

- Build a read-only context-router experiment on the existing schema.
- Compare it with QMD-only retrieval on decision reuse, relevance, latency, and tokens.
- Change schema or retire `## Links` only after the consumer experiment proves the need.

### Batch 5: Proof and distribution

- Benchmark Plastic, bare-agent work, Spec Kit, OpenSpec, BMAD, and GSD on preregistered tasks.
- Publish tasks, prompts, raw transcripts, artifacts, costs, recovery events, and blind review rubrics.
- Ship one 90-second surface and one full case study.
- Use marketplaces as the first measured channel, not as assumed causation.
- Improve project governance and bus factor before seeking broad company adoption.

## Final verdict on Claude's report

Adopt:

- stay on Ruby;
- attack process count, QMD probing, and repeated parsing;
- codify deterministic state transitions;
- build a real graph consumer;
- benchmark the full process;
- make Plastic understandable in 90 seconds.

Modify:

- fix SessionStart's store shape as a two-concept data-model repair, not a caller-only path substitution;
- split always-on context, but preserve the minimal invariants every harness needs;
- compress agent and human reports instead of deleting the information-bearing handoff;
- make Tier S fast within one stable state schema before inventing another;
- prototype graph retrieval before changing edges or deleting `## Links`;
- present marketplace and positioning claims as measurable experiments.

Reject:

- changing only SessionStart's root argument to `~/.plastic/store` without updating `hook-session-start` path construction and root consumers;
- "no flock anywhere" and "zero concurrency tests";
- exact token, latency, LOC, and savings claims without a reproducible bundle;
- treating AGENTS.md research as evidence against specifications generally;
- claiming the category is empty, the term has one origin, or Plastic's uniqueness is already proved;
- deleting completion-report contracts because a degraded filesystem fallback exists;
- publishing the six-batch roadmap as if its estimates were verified.

The best version of the original conclusion is narrower and stronger:

> Plastic already has a valuable deterministic core. Make its public truth consistent, make its safety concurrent, make its hot path measurable and fast, then prove that durable intent-to-outcome work beats both bare-agent delivery and competing process systems. Do not rewrite it in Go or Crystal, change its graph schema, or market it as unique until those experiments say to.
