# Plastic Adversarial Review: a skeptical second pass on the 2026-08-02 system review

Date: 2026-08-02. Subject: the findings in `2026-08-02-plastic-system-review.md`.

How this was made: four independent skeptic agents, each briefed as a KISS-minded senior architect and told to refute (not confirm) one claim cluster of the first review: performance and language, workflow and economics, concurrency defects, and market research. Each re-derived from source, re-measured on this machine, ran hermetic reproductions against copies (never the real store), or re-verified against primary web sources. The four raw skeptic reports sit in `2026-08-02-agent-reports/` next to the first review's raw reports.

Read this together with the first review. Where the two disagree, this document says so explicitly and states which one to trust and why.

---

## 1. Scorecard

| First review section | Verdict after the adversarial pass |
|---|---|
| 3. Speed measurements | Numbers survive; the causal model and per-fix savings arithmetic do not. Hooks run in parallel, not sequentially |
| 3. Ranked speed fixes | Reordered. The top user-felt cost (the prompt path, ~1 second per real prompt) was missing entirely; one proposed fix is better replaced by deletion, another by laziness |
| 4. Token economics | Directionally right, honest in occupancy terms, but the headline should be 61x not 78x (wrong tier topology), and in dollars the entire prize is small: the boot bill is about $1.39 per delivery |
| 4. Ceremony cuts | Partly refuted. The report-contract deletion is wrong: mandated reviews caught real defects, and the briefings implement recorded owner rulings |
| 5. Loops engineering | Direction confirmed, but batch 4 duplicates work the store already decided: intent 213 holds an advisor verdict on the same question. Resume it, do not re-plan it |
| 6. Graph engineering | Strengthened. The strongest-surviving proposal in the first review |
| 7. Codify vs agent | Confirmed in direction, redirected in execution (through intent 213's "scripts only, no new concepts" verdict) |
| 8. Concurrency | Most defects confirmed by reproduction, but the attribution of the flagship bug is wrong, the proposed one-line fix for the store-path defect would break the hook, and a better root cause was found |
| 9. Market landscape | More accurate than expected (papers real, most stars exact), but the errors sit precisely under the GTM recommendations |
| 10. GTM playbook | Two of the top three plays need rework: the marketplace step-function story is survivorship bias, and the benchmark as proposed is not feasible for a solo maintainer |
| 11. Stay on Ruby | Conclusion survives; the argument was weaker than the one available. The real distribution problem (macOS ships Ruby 2.6, Plastic requires 3.0) went unnoticed |
| 12. Action plan | Batches 1 and 2 survive with corrections; 3 is weakened; 4 redirects to intent 213; 5 is strengthened; 6 needs the market errata and a shorter clock |

---

## 2. What survives untouched

Worth stating first, because a devil's advocate pass that only lists overturns misleads in the other direction.

- The core architectural diagnosis holds: every gate is a refusal, every advance is prose, and that is why the instruction layer is heavy. Nobody refuted it; the store itself confirms it (intent 213 reached the same conclusion in July).
- The headline latency fix holds and is conservative: measured again, today's edit path is 703ms and the merged-process floor is 56ms.
- `--disable-gems` is verified safe across all 17 hook scripts and every major CLI script. Not assumed: load-tested.
- The QMD probe really does fire on every retrieval call with no cache or guard.
- `disarm_auto` discarding the lock-release result, the non-atomic lock write, and the build-auto-in-tmp defect all reproduced exactly as described.
- Stay on Ruby stands. The skeptic went looking for the Go case and came back with a sharper reason it fails: 80 of 128 test files load the Ruby modules directly, so a rewrite discards about 62 percent of the suite.
- The graph proposal (context routing) survived a direct KISS attack: only 21 percent of edges are derivable from folgezettel IDs, so the ID scheme cannot substitute for the graph, and QMD only covers the pull case (agent knows to ask), not the push case (routing without a query).
- Most of the market research: all three arXiv papers are real with near-verbatim findings, every funding round checks out, 14 of 16 star counts are accurate to three digits, and Superpowers genuinely has 265k stars.

---

## 3. The overturns

### 3.1 The physics of hook latency was wrong

Claude Code runs all matching hooks in parallel and deduplicates identical commands (documented behavior, confirmed by measurement). The first review's additive model (five gates summing to 854ms) is not what happens; the measured 854ms is real wall clock, but it comes from CPU contention among five simultaneous Ruby interpreter starts plus one genuinely serial PostToolUse hook.

Why it matters: every per-fix saving expressed as "X ms per spawn times N spawns" over-counts by roughly N. Corrected numbers:

| Fix | First review claimed | Measured under parallel execution |
|---|---|---|
| `--disable-gems` | ~390ms per edit | ~106ms per edit |
| Delete bash shims | 250-300ms per edit, effort S | ~455ms per edit, but effort M (see 3.2) |
| Merge 5 hooks into one process | "4 spawns saved" | floor of 56ms per edit; subsumes both fixes above |

The KISS conclusion is stronger than the original: skip the intermediate fixes and go straight to one merged gate process. It is the floor, and it makes the other two fixes unnecessary.

### 3.2 Deleting the shims is not free, and the users it hurts are not you

The shims do three things besides parse JSON: a 9ms bash guard (`[ -f ~/.plastic/INDEX.md ] || exit 0`) that saves a Ruby spawn on every tool call for every user who does not have Plastic installed globally; install-time path rebinding; and ARGV marshalling for four scripts that read positional arguments, not stdin. "Hook scripts read stdin directly" means rewriting four entrypoints and their tests. Still worth doing as part of the merged-gate work, but it is effort M with a design decision inside it, not a mechanical deletion.

### 3.3 The top felt latency was not in the report at all

The first review measured `qmd-search` at 154ms. That is the skipped path (prompts under 10 characters, or exactly "continue"). Real prompts pay 1,024 to 1,174ms, bounded only by a 2-second timeout, and the full UserPromptSubmit path measures 919ms in parallel. Unlike the edit hooks, which hide behind a mid-turn spinner, the prompt path delays the first token of every reply. It is the latency a user actually attributes to Plastic.

Corrected perceived-latency ranking: prompt path (919ms, felt every message) > session boot (1,020ms, felt once) > edit path (703-872ms, hidden). The first review ranked the edit path first and the prompt path nowhere.

### 3.4 The retrieval gate should be deleted, not optimized

The first review proposed caching the QMD freshness probe. Two simpler options dominate. Laziness: move the capability check inside the only branch that needs it, so the many reads that never target a store pay nothing (measured 13ms without the probe). Or deletion: the gate is advisory by construction, its output is a hint string, the same guidance already ships in the UserPromptSubmit line and AGENTS.md, and at ~150 retrieval calls per delivery it costs about 88 seconds. A hint that costs 88 seconds per delivery and duplicates two other surfaces is a deletion candidate, and deletion is a smaller diff than a cache with TTL and invalidation.

### 3.5 One of the two named critical bugs had the wrong fix, and the flagship bug had the wrong cause

The store-path defect is real (three malformed bridges live in /tmp right now, all for intent 28), but the first review's "one-line fix at hooks/session-start:9" is wrong and would break the hook: `hook-session-start:52` appends `/store` itself, so changing the shim argument produces `store/store/`. The actual defect is inside `hook-session-start:52-54`, where the un-suffixed root is passed as `store:` into `Bridge.derive`. Fix it there.

Bigger: the SessionStart-wipes-armed-bridge mechanism is real (reproduced) but cannot be the cause of the documented worktree-flap bugs. The hook resolves its session from the environment variable or PID, never stdin, and it only ever derives for a single Active intent in the global store; the flap bugs happened on project-store intents. The reproduction found the actual root cause:

**`arm` writes the virgin bridge to disk before acquiring the lock** (`Bridge.derive` writes at `bridge.rb:820`; `arm` calls it at `:896`, before `Lock.acquire` at `:902`). Every failed or repairing re-arm therefore guts the armed bridge first and raises second: auto off, worktree pointer null, isolation silently open, durable lock intact. On top of that, `Worktree.provision` (`worktree.rb:145-170`) unconditionally replaces the bridge's worktree block, and the code pointer stays null unless `git worktree add` succeeds, so one transient git failure overwrites a good pointer with null. That is the pointer flap, and it lives in `arm` and `repair_lock`, not SessionStart. The fix is small: have `derive` return the hash and let `arm` persist once, at the end, after acquire and provision succeed; and make `provision` preserve an existing pointer on failure.

Also corrected: "no flock anywhere" is false (`scripts/write-config:64` holds an exclusive flock across a read-modify-write with temp-then-rename, covered by a genuine two-thread subprocess race test), and "zero concurrency tests" is false by the same file. This flips the fix framing from "invent atomic locking" to "port the write-config pattern", precedent-backed and shipping with a test template. The "permanent poison pill" heartbeat scenario is a recoverable one-command stall, the takeover-rollback hole is unreachable today (nothing acquires maintenance locks), and lease expiry never blocks the owner (freshness only opens an audited takeover window), so those three drop below the cut line.

### 3.6 The economics were overstated at the headline and understated at the config file

Three corrections compound:

1. The "medium delivery" was measured at tier-L topology (7 sessions). The shipped M topology is 5 sessions, so the headline is about 61x, not 78x.
2. In dollars, with caching at current rates, the entire 5-session boot bill is about $1.39 per delivery, and the PLASTIC.md split is worth about $0.57 per delivery, roughly $200 across every delivery ever made. Real, worth taking, not a week-of-work prize. (In context-occupancy terms the split remains fully justified; caching reduces dollars, not occupancy.)
3. The first review never opened `config.yml`. One line there (`agents.models.plastic-brainstorming: fable`) makes a single brainstorming session cost about $3.34, which is 2.4 times the entire boot bill it spent a batch of prose surgery to shrink. Whether to change it is an owner call (the advisor-cost ruling may extend to it deliberately), but a review that ranks savings must rank the config lever first, and it did not.

Also: 43 percent of the 354 real deliveries have zero action files and 30 percent have six or fewer checklist items, so the small-work-pays-large-work-overhead complaint is genuine and not a strawman; but the system's own ledgers max at 15 recorded steps, so "52 steps" describes internal tool calls, not anything the user experiences. Both reviews should quote 15 as the honest ceiling of what the record shows.

### 3.7 The ceremony cuts went one cut too far

The report-contract deletion is refuted by the store itself. `scripts/agent-report` is a documented fallback for when a child agent returns nothing usable; it reports which files exist and cannot report what a specialist judged. And the mandated review output has caught real defects on record: the Opus gate review in intent 202 caught a date parser that hid 83 percent of project history from the next-work ranking, and the reviewer in intent 96 caught a skeleton-key bug in the locking model. The briefings are also the surface that recorded owner rulings (EM-to-CTO reports, review-before-merge) act on; intent 177 exists solely to protect that human decision point.

What still stands from the verbosity audit: the Announce mandates, the triple-telling at Done, and the duplicated byte-identical blocks are real waste. Trim those. Keep the reviewer envelope and the human briefings.

The skill-merge arithmetic also does not reproduce (the humanizer and skill-evaluating byte counts match neither the body nor the directory), and three of the six proposed deletions defend themselves: the humanizer is the enforcement hook for the no-AI-tells rule, skill-evaluating enforces an owner ruling born from a real failure (intent 166), and intent-grilling is a user-invoked command with tuned style. The install-family merge would make any single lifecycle operation load all four operations' prose. The right number is closer to "a few merges and trims" than "47 percent".

### 3.8 Batch 4 already exists in the store

Intent 213 (snappy intent delivery) holds a Fable advisor verdict from 2026-07-18 covering the same ground as the first review's batch 4: bundle scripts, moving code-before-How enforcement into the hook layer (it names the same `bridge.rb` line), and expressing settled intent through the existing Tier line. Its winning rival was: scripts only, no new concepts, convert hot fixed procedures one at a time. The correct action is to resume intent 213's three open decisions, not to author a fresh plan that re-derives a decision the store already holds. (This is also a neat demonstration of the first review's own graph point: a context-routing consumer would have surfaced 213 automatically.)

The tier same-structure invariant also survives: `tiers.md` states the engineering reason (per-tier gate logic would break state derivability) and the first review's scoring contradicted itself by grading tier down on gate count while its own cost model says dispatches (which tier does cut) are 77 percent of overhead.

### 3.9 Market corrections that change decisions

| Claim in first review | Corrected |
|---|---|
| Superpowers "137k+ installs from one marketplace listing" | 1,009,371 installs, and the causality is inverted: the repo launched the same day plugins entered public beta and the HN wave preceded install accumulation. The marketplace was the rail, not the engine. Listing is table stakes, not a step function |
| "Willison's paragraph is the identifiable pivot" | The 435-point HN thread was Jesse Vincent's own post; Willison's submission got 5 points. Earned endorsements remain valuable; that specific causal story is dead |
| OpenSpec ~28k | 63,464. It is the field's number three, ahead of BMAD, and the closest philosophical rival on the change-vs-idea axis |
| Taskmaster "150k+ downloads" | 70,663 npm downloads per month; repo stale since April |
| Agent OS "best business (paid membership)" | The $299/yr is Builder Methods Pro, a separate product; Agent OS itself is free. The monetization recommendation copied a misattribution (the shape is still sensible, but attribute it correctly) |
| "Only four repos ship intent as a typed artifact, largest 495 stars" | Indefensible. At least nine do, and the example named fails the claim's own predicate. Replace with a comparative claim about what a Plastic intent record carries that a beads issue or an OpenSpec change does not |
| GSD "$500k rug-pull" | No source states an amount; the originating report says it is unknown. Keep the abandonment fact, drop the number |
| ETH paper "imperative org rules do help" | The paper measured behavior compliance, not success; the developer-file improvement was +2.4 percent at p=0.21, not significant. It is the authors' hedged recommendation, not a demonstrated result |
| Kiro GA March 2026; Amp handoff deleted; Aider dormant 12 months; Traycer 302k installs | GA 2025-11-17; handoff never deleted; Aider shipped 0.86.2 on 2026-02-12 via PyPI; Traycer 41,245 installs |
| LinkedIn "82 percent of B2B leads", "8x personal profiles", "70 percent learn from YouTube" | Folklore or mismeasured; no primary studies. Drop the statistics, keep the channel logic on its own merits |

### 3.10 The window is months, not quarters

The largest market omission: first-party commoditization. Claude Code now ships persistent task tools (typed states, dependencies, file-locked claiming, surviving resume) and default-on memory with per-agent git-checked memory directories. GitHub shipped typed issue fields, sub-issue hierarchies, agent sessions inside issues, and agent audit trails. Google made plans and task lists first-class reviewable artifacts in Antigravity, and Gemini CLI writes plans to disk. HumanLayer's ACE-FCA gives away a research-plan-implement artifact methodology that won a 405-point HN thread. Neutral orchestrators (opencode at ~192k, Orca, emdash) absorb task management by importing the tracker a team already has rather than inventing an artifact, which is the strongest single argument against a standalone artifact store.

The positioning claim that survives commoditization, stated narrowly: a durable, human-authorable, on-disk, version-controlled work artifact with a lifecycle that outlives any session and is portable across repos, vendors, and sessions, with a stable public schema and git history. Nobody ships that. But session logs, plan files, approval gates, per-repo memory, and audit trails are now free platform features. Batch 6 should assume months, not quarters.

Two smaller GTM rewrites: the four-arm benchmark is not feasible for a solo maintainer (a funded ETH lab with a purpose-built 138-instance benchmark could not reach significance on a simpler question; a maintainer-authored victory benchmark carries near-zero persuasive weight anyway). The feasible, credible version is a fixed 20-task suite with full published transcripts and an honest cost-and-time tax number, framed as disclosure: "Plastic costs +N percent tokens and +M minutes, and here is what you get for it." Buildable in a week, and it answers the ceremony objection head-on. The claim only Plastic can make, and should instrument: decision recall and rework avoided. And one encouraging datapoint the first review missed: `@zalom/plastic` did 5,563 npm downloads last month against 9 stars; the star count is not the only traction signal.

---

## 4. New findings from this pass

| # | Finding | Why it matters |
|---|---|---|
| 1 | **The create gate ships dead for plugin-marketplace users.** `hooks/create-gate` is committed with file mode 100644 (non-executable). The plugin path bare-execs it: permission denied, exit 126, on every Write and Edit. It works locally only because the npm installer chmods its copy | Invalidates a claimed strength ("deterministic enforcement") for exactly the channel the GTM plan ranks first. One-character fix (`git update-index --chmod=+x`) plus a doctor check |
| 2 | **There is an escape log but no denial log.** `~/.plastic/.cache/gate-escapes.log` records 756 uses of the `# plastic-ok` escape hatch in one month, by the author. Nothing records denials, so the system cannot answer "which gate ever blocked something that mattered" | Instrument before optimizing: one append per denial, read it in 30 days, delete gates that never fired. Cheaper than making five gates fast |
| 3 | **The real zero-to-one problem is the Ruby floor, not latency.** Stock macOS ships Ruby 2.6.10; preflight requires 3.0.0. A clean-Mac marketplace user cannot start | Test whether the scripts actually run on 2.6 and lower the floor, or bootstrap a Ruby in postinstall. Untested today. This, not Go, is the distribution question |
| 4 | The derive-before-acquire root cause (3.5) with its two-part small fix | Explains the documented bug family the first review attributed elsewhere |
| 5 | The prompt-path measurement (3.3) | The top user-felt latency, previously invisible |
| 6 | The write-config precedent (3.5) | The concurrency fix becomes a port, not an invention |
| 7 | Minor errata: PLASTIC.md is 53,558 bytes (~13.4k tokens), not 55,558/13.9k, repeated three times; the harness-adapters "contradiction" at lines 117/126 is two different mechanisms under two headings, not a contradiction | Correct before quoting |

---

## 5. The revised action plan

Amendments to the first review's six batches; unamended items stand.

| Batch | Amendment |
|---|---|
| 1. Snappy | Reorder by felt latency: (a) fix the prompt path first, about 1 second off every real prompt (make the QMD search async, cache-backed, or skip-by-default); (b) delete or lazy-load the retrieval gate rather than caching it; (c) go straight to one merged gate process (56ms floor) instead of the shim-deletion and disable-gems intermediates; (d) fix the create-gate file mode and add a doctor check for executable hooks; (e) add denial logging now, and in 30 days delete any gate with zero denials |
| 2. Safe | Replace the SessionStart-first framing: (a) move the bridge write in `arm` to after lock acquire and provision; (b) make `provision` preserve an existing worktree pointer on failure; (c) fix the store path inside `hook-session-start:52-54`, not the shim; (d) use the `Lock.release` result in `disarm_auto`; (e) make `Lock.write` atomic by porting the write-config pattern, and clone its race test. Drop from the batch: takeover rollback, heartbeat changes, and the build-auto move (defensible someday, not now) |
| 3. Lean | Keep the PLASTIC.md split (occupancy justifies it; price it honestly at ~$0.57 per delivery). Keep the Announce/triple-telling trims and the PreCompact fix. Drop the report-contract deletion and the install-family merge. Re-measure the skill-merge numbers before acting; expect "some" not "47 percent". Add: surface the model-config cost table to the owner (one line of config outweighs the whole batch in dollars; owner decides) |
| 4. Codified | Do not plan this fresh. Resume intent 213 and its three open decisions; fold the first review's verb list into that intent as candidate procedures under its "scripts only, no new concepts" verdict. Tier stays structurally invariant per its own stated rationale; add only the tier-stamp enforcement |
| 5. Remembering | Proceed as written; this pass strengthened it. Note for motivation: a context router would have surfaced intent 213 before batch 4 was drafted |
| 6. Seen | Apply the errata in 3.9 before anything ships. Marketplace listing becomes table stakes; the launch moment (HN-grade post) takes the top slot. Replace the four-arm benchmark with the 20-task transparency suite plus the cost-tax disclosure number. Fix the Ruby-floor problem before listing (finding 3), or the first marketplace cohort meets a broken create gate and a failed preflight. Assume the window is months |

---

## 6. Closing judgment

The first review was right about the shape of the problem and wrong in places about its mechanics, its arithmetic, and two of its remedies. Its strongest sections (the latency measurements, the refusal-versus-advance diagnosis, the graph proposal, the Ruby verdict) came through the adversarial pass intact or strengthened. Its weakest habit was measuring a thing correctly and then attributing it to the wrong cause: hooks that run in parallel billed as a sum, a bridge wipe blamed on the wrong hook, a growth curve credited to the wrong blog post, a membership price attached to the wrong product.

The KISS lesson that generalizes: in four separate places, the cheapest correct move was not the one the first review proposed. Delete the retrieval gate rather than cache it. Merge the gates rather than shave each one. Port the existing flock pattern rather than design locking. Resume the existing intent rather than write a new plan. Before optimizing anything, check whether it should exist; before building anything, check whether the store already decided it.
