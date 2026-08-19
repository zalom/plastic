# Agent report: code & runtime layer (arch-code)

(Read-only analysis, timings measured on arm64-darwin25, Ruby 4.0.3 +YJIT via mise.)

## 0. Executive summary
1. Hook latency ~4x higher than necessary; cause is architecture, not language. Same three gates: 970ms today vs 251ms after two mechanical fixes (--disable-gems, drop bash JSON re-parse shims). Measured.
2. `qmd status` (526ms) shells out on EVERY Read/Grep/Glob/Bash call to decide whether to print an advisory hint that never blocks.
3. SessionStart injects 55,558 bytes (~13.9k tokens) — the entire PLASTIC.md — every session; 3.7x the always-on cost of the whole 87-file skills tree.
Recommendation: stay on Ruby (see 5).

## 1. Executable surface
- bin/plastic.js: 58 LOC JS dispatch shim only (Node = distribution, not implementation).
- scripts/*: 48 files, 11,143 LOC (46 Ruby, 2 bash). scripts/lib/*.rb: 37 files, 8,828 LOC. hooks/*: 18 bash-3.2 launcher shims (~330 LOC, themselves a defect). test/: 128 files, 28,032 LOC. skills/: 87 md files, 8,434 LOC. Runtime total non-test: 20,494 LOC, ~99% Ruby.
- God objects: doctor.rb 3,016 LOC (24 checks; required wholesale by hook-session-start:12); bridge.rb 1,620 LOC / 71 module methods / 1 private; installer_core.rb 1,430; dashboard.rb 1,037; end-intent 702; lock.rb 550.

## 2. Performance (measured)
Per event: SessionStart 1,020ms; EVERY user prompt 1,226ms (continue+future-intent-check+auto-arm+qmd-search); every Write/Edit 854ms (5 gates + PostToolUse gate-check); every Read/Grep/Glob 704ms (retrieval-gate); every Bash ~966ms; statusline 66ms.
Individually: retrieval-gate 839, code-gate 570, gate-check 501, lock-gate 406, savepoint-pre 388, auto-arm 309, links-gate 285, bash-gate 262, future-intent-check 171, qmd-search 154, continue 149, create-gate 27. Wiring: hooks/hooks.json:32-147.

Where time goes:
(a) qmd status on every retrieval: hook-retrieval-gate:95 -> QmdSync.fresh? (qmd_sync.rb:144-150) spawns `qmd status` = 526ms, purely to print a hint (gate is advisory by design, :8-11). Session/60s-TTL cache removes ~590ms per retrieval call.
(b) RubyGems init 39ms/spawn free to remove: ruby -e '' = 55ms; ruby --disable-gems = 16ms; --disable-gems + require json = 22ms; native binary = 5ms. All runtime requires are stdlib; only doctor.rb/preflight.rb touch rubygems (Gem::Version). Verified hook-lock-gate + hook-bash-gate run correctly under --disable-gems.
(c) Redundant spawns: hooks/code-gate spawns Ruby 4x (three `ruby -rjson` parses of the SAME stdin JSON, then the gate). code-gate 4, lock-gate 3, gate-check 3, savepoint-pre 2, auto-arm 2, continue 2, future-intent-check 2. One Write/Edit ≈ 10 Ruby interpreters, ~8 exist only to re-parse one JSON blob. 7 shims contain literal JSON.parse(STDIN.read); code-gate/lock-gate carry byte-identical 8-line extraction block.
(d) Library parse per spawn: bridge.rb +66ms, retrieval_gate +66ms, links_gate +55ms, lock.rb +23ms, qmd_sync +16ms; hook-session-start requires all of doctor.rb (+126ms).
(e) /tmp bridge glob: discover_bridge (bridge.rb:204-209) JSON.parses EVERY /tmp/plastic-*.json (17 present now) → ~100 JSON parses per single edit.
(f) doctor --core 197ms; full 1,073ms.

Headline: same 3 gates, 5 iterations: current 970ms vs 251ms direct+--disable-gems+no-re-parse = 74% reduction, zero rewrite.

Ranked speed wins:
1. Cache QMD freshness — ~590ms/retrieval call (S)
2. Delete bash shims; hooks read stdin directly — ~250-300ms/edit (S)
3. --disable-gems on hot invocations — ~390ms/edit (XS)
4. Merge 5 PreToolUse Write/Edit hooks into one process — ~4 spawns (M)
5. Stop requiring doctor.rb from hook-session-start — ~126ms/session (XS)
6. Index /tmp bridges by key, stop glob+parse-all — 10-40ms/gate (S)
7. Trim 55KB SessionStart injection — ~13k tokens/session (M)
Wins 1-3 mechanical; Write/Edit 854→<250ms; Read 704→~50ms.

Test suite: 1,837 runs, 6,406 assertions, green, 165.7s at ~6% CPU duty cycle (subprocess-bound). Worst: restore_intent_v1_test 28.1s, dashboard_test 23.9s, codex_hooks_test 12.4s. --disable-gems helps here too. Caveat: only the documented loader command runs the whole suite (glob form silently runs one file).

## 3. Code quality
Dead code (~660 LOC, zero references): scripts/migrate-folgezettel (535), migrate-to-global (96), hash-intent. skills/_active-intent-gate.md ships to users, read by zero skills, while 3 skills inline divergent copies. ~95KB evals/*.json installs with no runtime consumer (~18% of installed skill size).

Consolidation:
1. Delete the 18 bash shims (kills bash-3.2 constraint surface entirely; -300ms/edit, -330 LOC).
2. Split bridge.rb: BashWriteTargets (~224 LOC pure), Savepoint (~234), GateNarration (~44), BridgeStore (~120, concentrates ENV coupling).
3. One gate process per tool call (Gate::Context computed once; the 5 hooks each re-derive plastic_home/session/solo_delivery?).
4. Add store-commit verb: `git add . && git commit` retyped in 11 skill locations; `git add .` in a parallel store IS the documented sweep-up bug.
5. `plastic-lock arm`: 640-char inline ruby -e arm one-liner pasted in 3 skills; plastic-lock has 8 verbs but no arm.
6. Extract IntentIndex (bridge.rb:278-388) into store layer.
7. Delete dead migrations; exclude evals/ from install manifest (-18% install size).
8. Split doctor.rb so --core doesn't load the whole file.

Error handling: fail-open deliberate and consistent in gates (matches ruling). Concern: intent_active? (bridge.rb:335-337) rescues everything to false and purge_done_bridges then deletes ANOTHER session's bridge on that basis — fail-open into deleting someone else's state.

## 4. Codify-vs-agent audit
36 skills: 4,356 LOC SKILL.md + 4,078 references. ~40% of lifecycle-skill content is deterministic procedure; restated 3-11x, already diverged in 3 places (~350 LOC duplicated prompt text).

| Behavior | Currently | Should be |
|---|---|---|
| Move intent Future→Active + commit | prompt only (no script; end-intent owns the reverse) | scripts/activate-intent |
| Terminal close (6 steps) | intent-executing:91-93 AND :118-120 hand-write, bypassing end-intent — live drift vs intent-ending:171-174 | end-intent (exists) |
| Store auto-commit | 11 hand-typed git add . sites | scripts/store-commit --paths |
| Bridge arm | 640-char ruby -e pasted 3x | plastic-lock arm --mode |
| INDEX placement on create | new-intent:15 refuses; skill hand-edits | new-intent --index active --cluster |
| Reciprocal sources/chain edits | hand-edited both sides though link-suggest --record exists | link-suggest --record |
| Version bump + CHANGELOG | hand-edited; release_guard only checks after | scripts/bump-version |
| Doctor fixes | manual op table | doctor.rb --fix (fixable:true + fix_hint already emitted) |
| Store frontmatter scan | raw bash loop w/ split("---") in 2 skills (breaks on --- in body) | scripts/list-intents --json |
| Advisor config write | "read YAML, write back" prose | scripts/write-config (exists, bypassed) |

Correctly left to agent: speccing, brainstorming, grilling, humanizer, skill-evaluating, continuing router. Reference proof: intent-locking (100% script) and intent-ending (~90% script) are among the SHORTEST skills — codifying shrinks prompt.

Context load: ~3.7k tok always-on (descriptions), ~51.6k trigger-gated, ~46k demand-gated, ~24k never loaded (evals). Progressive disclosure structurally sound except: auto/SKILL.md 24.7KB (most-triggered, 23% over own budget, duplicates its never-Fable paragraph at :14-24 and :135-141) and the 55,558-byte SessionStart injection (hook-session-start:123-126,306).

## 5. Language: STAY ON RUBY
Startup floors: ruby 55ms; ruby --disable-gems 16ms; node 45ms; native binary 5ms. Go/Crystal buys ~11ms/spawn over --disable-gems ≈ ~66ms/edit, while architectural fixes are worth ~600ms. Work is I/O and subprocess-bound (git shell-outs; qmd status 526ms is language-invariant). Rewrite cost: ~20,500 LOC + discarding a green 1,837-test suite that is the main protection against the §6 concurrency defects (which a rewrite would likely reintroduce). Distribution: npm path works today, no per-platform build matrix; single binary = 4+ cross-compiled artifacts per release. Do instead: --disable-gems → delete shims → cache QMD probe → merge gates. Revisit compiled core only if post-fix hook count makes the 16ms floor dominate — with numbers.

## 6. Fragility
No flock anywhere; only O_EXCL at creation (lock.rb:143-146, 456-459); all later mutation unsynchronized. Zero concurrency tests (128 files, all single-process; the TOCTOU test tests ordering, not a race).

Critical:
1. SessionStart silently wipes an armed bridge: hooks.json:3-18 fires on startup/resume/clear/compact; hook-session-start:47-54 Bridge.derive writes a VIRGIN bridge (auto:false, worktree nil) to the same key (bridge.rb:770-822). This is the reproducible mechanism for BOTH documented bugs — the worktree pointer is reset to null on every resume, not raced.
2. Derived-key aliasing defeats the lock: derive_key hashes only store+intent_id (bridge.rb:112); two session-less processes get same key AND owner_session; Lock.acquire returns :owned to both (verified).
3. build.auto is authoritative state in /tmp: code_gate_decision nil unless build["auto"] (bridge.rb:1104); /tmp wipe silently disables the pre-How code gate; repair_lock can't recover it; no warning. The one place "bridge is only a cache" is false.
4. disarm_auto trusts cache over lock file (bridge.rb:997-1002), contradicting D2 "lock file wins" (lock.rb:15-16); on clobbered bridge Lock.release returns :not_owner and the return is DISCARDED — lock silently orphaned; with 2 bridges and no intent_id can disarm the wrong intent and remove the sibling's worktree (bridge.rb:963-991).
5. Live store-shape defect: hooks/session-start:9 passes $HOME/.plastic while everything else uses ~/.plastic/store; both shapes coexist in /tmp NOW (intent 28 vs 27); under malformed shape intent_active? reads ~/INDEX.md → false → purge_done_bridges treats the Active intent's bridge as deletable by any other session.

High: Lock.write non-atomic (no tmp+rename, lock.rb:295-297) → torn read makes true owner fail holds?, repair deletes + re-acquires = two owners. Lock.heartbeat holds?-then-touch (:196-200) can recreate a 0-byte lock that is simultaneously corrupt? and fresh? — permanent poison pill. takeover deletes-then-acquires with no rollback (:280-283). plastic-lock claim uses release_claim(force:true) (scripts/plastic-lock:208) bypassing ownership. add_delegate/update_delegate_status read-modify-write unlocked (lock.rb:204-249) — dropped registration denies that subagent every write.

Medium: 30-min lease on wall-clock mtime (NTP/suspend flips); host recorded never read; heartbeats only fire from WRITE-path hooks so 30 min of reading/planning/tests expires the lease under a live owner; rebuild_savepoint overwrites ledger → every takeover audit record erasable; Process.pid fallback session id (PID reuse); session resolution inconsistent across 6 callers (hook-auto-arm:29, plastic-lock:64 read ENV only); Lock::TYPES includes maintenance, never acquired.

Bg-job resume: lock gate hard-denies on new session id (bridge.rb:1206-1216) while old bridge becomes invisible (:243-246) → worktree confinement silently stops while writes get blocked; solo_delivery? can't rescue (compares owner_session==session, :1164); only in-code recovery `plastic-lock release --session <old>` (lock.rb:258) is undocumented in CLI usage.

Fix order: #5 (one-line) and #1 (guard derive when bridge armed) first; then atomic Lock.write + flock on RMW sites; then move build.auto out of /tmp into the intent dir (makes "bridge is only a cache" true); add first concurrency test.
