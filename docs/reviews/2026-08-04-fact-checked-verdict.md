# Plastic Improvement Verdict (Fact-Checked)

Fact-check date: 2026-08-04. Subject: Plastic v1.8.0.

This document is the verified synthesis of the three reviews in this directory: the original system review (2026-08-02-plastic-system-review.md), the adversarial pass (2026-08-02-adversarial-review.md), and the owner's Codex verdict (2026-08-02-plastic-system-review-codex-verdict.md). Five parallel verification agents re-checked about 75 claims against the code, live measurements, the intent stores, and primary web sources: roughly 52 confirmed, 9 corrected, 14 confirmed in direction with softer exact numbers. Where the reviews disagreed, the value below is the one that survived checking.

Measurement note: latency numbers were taken under machine load and vary between passes by 1.3x to 2x. The one number that reproduced exactly is the merged-gate floor (0.06 seconds). Hooks run under the global mise Ruby (4.0.3 here), not the repo's pinned 3.3.

Issues are ranked by value, context window and speed first.

## 1. Context window and speed

| # | Issue | What happens today | Fix | What you get |
|---|---|---|---|---|
| 1 | Whole rulebook loads every session | PLASTIC.md (53,558 bytes, about 13,400 tokens) is pasted into every session. A Tier M auto delivery boots 5 agents; each gets the full book, even chapters it never uses (executor gets lock-repair, reviewer gets install steps) | Small always-on core (about 5,000 tokens); each skill loads its own chapter when it runs | Every session and agent starts about 8,000 tokens lighter. Largest context saving available |
| 2 | Every message waits about 1 second | You press Enter; before the reply starts, the qmd-search hook searches the stores for related intents (about 1 second, bounded by a 2 second timeout). Paid on every message | Run the search in the background, or reuse a cached result | Replies start about one second sooner, every message. Biggest felt speedup |
| 3 | Every file read pays about 0.5 seconds for a reminder | On each Read/Grep/Glob/Bash, the retrieval-gate hook asks QMD "is your index fresh?" (0.4 to 0.5 seconds) just to maybe print "prefer qmd search". The same advice already sits in AGENTS.md and the per-message hint. About 150 calls per delivery, over a minute of waiting | Delete this hook. Making it lazy saves little: even the empty hook costs 0.14 seconds to start Ruby. Reindexing already happens automatically when an intent is delivered | Reads and searches respond instantly. Nothing lost |
| 4 | One edit starts 11 Ruby programs | One file edit fires 5 gates at once (code, lock, savepoint, links, create), which together start 11 Ruby processes, about 0.6 seconds per edit | One merged program running all five checks in a single process. Built and timed in the fact-check: 0.06 seconds | Edits approved about 10x faster; about half a minute saved per 50-edit delivery |
| 5 | Graph is written, never used for context | Intents record sources and chain (580 connections in the plastic store), but nothing reads them at work time. Example: intent 213 already held the advisor verdict for "make delivery snappy"; the review re-derived that plan from scratch because nothing brought 213 forward | Small script at work start: follow the intent's connections 2 steps out, paste only the neighbors' Outcome and Insights into the agent's context | Agents inherit decisions instead of re-deriving them. Biggest quality win of all three reviews |
| 6 | Same delivery reported 4 times | At Done: outcome.md, the EM-to-CTO report, a Done briefing, and a summary in the intent file. Plus 11 announcement rules in skills, 3 of which just say the skill's own name. The reviews themselves must stay: intent 202's review caught a bug hiding 166 of 200 done intents from the board ranking; intent 96's review caught the skeleton-key lock bug | One truth per audience: outcome.md for the record, one short report for the owner; delete duplicates and self-announcements | 1,000 to 2,000 fewer output tokens per delivery, nothing the owner reads is lost |
| 7 | Session start loads all of doctor | All 3,016 lines of doctor.rb load at boot (hook-session-start line 12) to run one small check | Split doctor so boot loads only its own check | Faster start for every session and agent |
| 8 | Gates never record what they block | The escape log shows 756 uses of the `# plastic-ok` escape in one month; blocks are written nowhere. Nobody can answer "has the links gate ever caught a real mistake?" | Write one line per block; read the log after 30 days | Proof of which gates earn their cost, and permission to delete the rest. Cheapest item on this list |

## 2. Bugs in locks and bridges

| # | Issue | What happens today | Fix | What you get |
|---|---|---|---|---|
| 9 | Arming wipes its own worktree pointer | Boarding an intent writes the bridge file first (bridge.rb:820 via :896), and takes the delivery lock after (:902). If the lock step fails, the bridge is already overwritten: worktree pointer empty, edits can land in the shared checkout. This is the true cause of the recorded "worktree pointer disappears" bugs | Write the bridge once, at the end, after lock and worktree both succeed; provision must keep an existing pointer on failure | That bug family becomes impossible |
| 10 | Session-start builds broken bridges | The hook mixes up Plastic home (~/.plastic) and the store (~/.plastic/store): the shim passes home, hook-session-start:54 forwards it as the store. At check time 2 of 8 bridges in /tmp had the wrong path (both intent 28); such a bridge reads the wrong INDEX.md, so a live bridge can be cleaned up as inactive | Keep home and store as two separate values inside hook-session-start (a one-line shim fix would produce store/store and break it) | No broken bridges, no cleanup of a live session |
| 11 | delivery.lock can get two owners | Lock writes are a plain overwrite (lock.rb:295-297). Two processes at the same moment: one reads a half-written file, thinks "not mine", takes the lock again: two owners. Delegate registration (lock.rb:204-249) has the same flaw: one registration can erase another, and that subagent then gets every write refused | Copy the safe pattern already in scripts/write-config:63-64 (file lock, write temp, rename) and clone its two-process test | Lock corruption impossible, using code the repo already trusts |
| 12 | Ending can orphan the lock | disarm clears the bridge but never checks the lock release result (bridge.rb:1001); a failed release leaves an orphan lock. With two intents in one session, disarm without an intent id can pick the wrong sibling (the repo's own bridge_collision_test documents the gap) | Check the release result; always pass the intent id | Clean endings, even with parallel deliveries |

## 3. Blockers for new users (before any marketplace listing)

| # | Issue | What happens today | Fix | What you get |
|---|---|---|---|---|
| 13 | Create gate dead for marketplace installs | hooks/create-gate is stored in git without execute permission (mode 100644). Plugin-marketplace installs get "permission denied", exit 126, before the gate runs (reproduced live). Local installs work only because the npm installer repairs the permission while copying (installer_core.rb:640) | One git permission change, a doctor check for executable hooks, one smoke test of the plugin dispatch path | The "gates you cannot skip" promise becomes true on the channel where new users arrive |
| 14 | A clean Mac cannot install | Preflight requires Ruby 3.0 (preflight.rb:19); macOS ships 2.6.10, install stops. All 42 scripts parse under 2.6 (syntax check), so lowering is realistic, but runtime calls are untested. Extra trap: a global RUBYOPT=--yjit crashes system Ruby 2.6 outright | Runtime-test on 2.6 and lower the floor, or bundle a Ruby; hooks clear RUBYOPT either way | First install works on a clean machine |

## 4. Process weight

| # | Issue | What happens today | Fix | What you get |
|---|---|---|---|---|
| 15 | "Codify the loop" already has an intent | Intent 213 holds the advisor verdict of 2026-07-18: convert hot procedures to scripts, one at a time, no new concepts; three decisions wait for the owner. It is a Future intent, never started | Activate 213 and run the normal cycle; fold the script list (next-step, boarding in one call, scoped store commits) into it | The work lands inside the intent that already decided how to do it |
| 16 | Small work pays the full price | A Tier S one-liner produces the same files, gates, and questions as Tier L; tiers only cut agent boots. Small is the common case: 44 percent of 356 completed deliveries had zero action files. (The "52 steps" figure was a model; the savepoint ledger never records more than 15) | Make S cheaper inside the same file structure: one thinker for Why plus How, short documents, one action, one executor. Keep the structure; gates and savepoint rebuild depend on it | Cheap small intents, no second rulebook |
| 17 | Compaction gives wrong instructions | The PreCompact hook orders a 5-step manual savepoint naming Build/Observe sections that no longer exist in the intent template | Replace the text with one call to the existing savepoint rebuild script | Compaction becomes a non-event |

## 5. Truth in docs and other harnesses

| # | Issue | What happens today | Fix | What you get |
|---|---|---|---|---|
| 18 | Docs describe removed machinery | Six places: AGENTS.md:101-102 and docs/architecture.md:199 and docs/internals.md:772-775 still describe the store worktree removed by intent 178; docs/architecture.md:215 and scripts/restore-intent-v1:145-146 reference the maintenance lock of intent 112, which was abandoned; README.md:152 has a broken sentence ("and and") | Update the six places to match the code: one worktree, one lock | Readers stop acting on instructions about removed machinery |
| 19 | Codex install still speaks Claude | Installed Codex skills carry 120 lines in 36 files referencing Claude constructs: CLAUDE_PLUGIN_ROOT, ~/.claude paths, /plastic- slash commands. Hermes gets files copied, nothing wired. Reality: one working harness, one partial, one packaging target | Rewrite paths per harness at install, add a leftover check, publish an honest support table. A codex binary now exists locally, so the untested fail-open patch parser can finally be tested live | A Codex install that works; claims that match reality |
| 20 | Dead files ship to every user | Two unused migration scripts (631 lines); one shared gate text no skill reads (skills carry drifted copies); 95,419 bytes of eval JSON, 18 percent of skill bytes, read only by the skill-evaluating maintenance skill | Delete the scripts, stop shipping evals, only a few measured skill merges (the "47 percent can go" claim did not survive checking) | Smaller, cleaner install |

## 6. Graph correctness

| # | Issue | What happens today | Fix | What you get |
|---|---|---|---|---|
| 21 | Recording mistakes live in the graph now | Four intents form a circle in sources: 22c -> 14 -> 13 -> 19a -> 22c. Sources means "born from", and birth cannot be circular; doctor has no check for it. Doctor also warns today about a broken cross-store link on global intent 27 | Add the circle check to the validator, repair the link, block duplicate intents at creation (candidate list already exists in link_suggestions.rb) | A graph the context router (row 5) can trust |

## 7. Proof and market

| # | Issue | What happens today | Fix | What you get |
|---|---|---|---|---|
| 22 | Numbers move with machine load | The same hook path measured 1 second in one pass and 0.5 seconds in another (busy machine). Only the merged-gate 0.06 seconds reproduced exactly. Hooks run under the global Ruby, not the repo pin | A bench command in the repo (fixed inputs, repeat counts) plus one real API-token measurement of an S, M, and L delivery (the "61x overhead" figure is still a paper model) | Honest before and after numbers for every fix; base of the public benchmark |
| 23 | Market verified; window is short | Confirmed 2026-08-04: Spec Kit 125k stars, OpenSpec 63.7k, BMAD 51.5k, Taskmaster 27.9k (idle since April), Superpowers 266k stars and just over 1 million marketplace installs. Plastic: 9 stars but 4,808 npm downloads last month. Platforms give the generic parts away (Claude Code tasks and memory, GitHub agent sessions, Antigravity plan artifacts), so the window is months | List only after rows 13 and 14; publish a 20-task suite with transcripts and an honest cost line; one launch-quality write-up; a second maintainer | Distribution built on claims that survive checking |

## Corrections applied by the fact-check

| Was claimed | Verified value |
|---|---|
| Retrieval gate: delete or lazy-load, roughly equal | Delete clearly wins; the lazy floor is 0.14 seconds, not 0.013 |
| Bash tool path costs about 1 second | About 0.47 seconds; bash-gate alone is cheap (0.11), the QMD probe dominates |
| Intent 213: resume it | It is a Future intent, never started; activate it |
| 3 dead migration scripts, about 660 lines | 2 scripts, 631 lines |
| Codex install: 76 Claude-specific lines | 120 lines across 36 files |
| npm downloads 5,563/month | 4,808/month (stars exactly 9) |
| disarm can remove another session's worktree | The gap is same-session, cross-intent, via the legacy no-intent-id fallback |
| 3 malformed bridges in /tmp | 2 of 8 at check time (transient; both intent 28) |
| 354 deliveries, 43 and 30 percent | 356 deliveries, 44.1 and 27.2 percent |
| 12 announcement rules | 11 (3 self-naming, exact) |

## Owner decisions (not intents)

| Decision | The numbers |
|---|---|
| Keep Fable for brainstorming? | Only model override in config.yml (agents.models.plastic-brainstorming: fable); about $3.34 per brainstorming session at current prices, versus about $1.39 for a whole delivery's boot cost |
| Ruby requirement | Lower the floor to 2.6 (needs a runtime test) versus bundle a Ruby with the installer (heavier, safer) |
| Money model | Free tool plus paid membership fits best; the $299/yr example belongs to Builder Methods Pro, a separate product from Agent OS |

## Claims that remain unverified

- "66 percent of instruction text is redundant": no reproducible classification exists; treat as a hypothesis.
- The 61x token overhead: a paper model, not a measured API trace; the bench command in row 22 makes it measurable.
- The ETH paper's "+2.4 percent at p=0.21" detail: abstract-level findings confirmed, that number needs the full text.
- The exact 3,675 lines of graph code: 2,317 is the countable core; the rest depends on scoping.
