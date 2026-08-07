---
name: plastic-intent-starting
description: >-
  Board a session onto an intent: take the lock FIRST, confirm savepoint state, ask auto or
  guided ONCE, then resume at the latest delivered station and run the cycle to Done. Use on
  `continuing --intent {id}`, when a new intent is registered and the user asks to work it,
  or when the user picks an intent to work. Requires the intent in INDEX `## Active`.
user-invocable: true
---

# Intent Starting — board a session onto an intent

`plastic-intent-starting` is the Start procedure. It boards a session onto one intent: take
the lock FIRST, confirm the delivery state, ask **auto or guided ONCE**, board at the latest
delivered station, then run the cycle to Done. The What → Why → How → Exec stations are the
train track; Start boards the train, the ending procedure (~93) exits it.

## Precondition + trigger

Fires when the user picks an intent to work, when an agent is told to continue a SPECIFIC
intent, or on `continuing --intent {id}` (the `continuing` → `starting` router is 106's job;
this skill is invokable standalone now).

If the intent is **terminal** (Done / Abandoned in INDEX): report only. Take NO lock, run NO
resume, do NOT reopen it. Summarize the outcome and ask what is next. Stop here.

## Lock FIRST (the spine)

The lock is non-negotiable and comes before any mutating work. The ACTION-3 lock-gate
enforces it: without a held lock, mutating writes to this active intent's dir are denied with
"run /plastic-intent-starting to lock and begin".

Read `../plastic-conventions/references/locks-and-worktrees.md` for delivery isolation: the
single-owner lock, claims, worktrees, solo mode, and the station ledger behind everything below.
This path resolves relative to this skill's own installed directory.

1. **Ensure the intent is in INDEX `## Active`.** If it sits in `## Future`, activate it
   (move it to `## Active`, auto-commit) before arming. Creation precedes activation, so a
   brand-new What intent is activated here, then locked.
2. **Self-heal the lock state first.** Run:
   `ruby ~/.plastic/scripts/plastic-lock fix --intent-dir <STORE>/<dir>`
   This is the one repair function (same one /plastic-lock exposes): it removes
   corrupt or legacy lock state and rebuilds the lock and bridge from disk for
   this session. If it reports `held`, another session owns the intent: STOP
   and tell the user who holds it. If it reports `stale`, ask the user before
   running `plastic-lock reclaim` (takeover is audited).
3. **Arm the bridge.** Which arm is chosen by the mode answer (below), but the lock itself is
   taken first. Reuse the arm one-liner shape from `plastic-auto`:
   ```bash
   # guided (lock only):
   ruby -r ~/.plastic/scripts/lib/bridge -e \
     'codex=ENV["CODEX_THREAD_ID"].to_s.strip; claude=ENV["CLAUDE_CODE_SESSION_ID"].to_s.strip; harness=!codex.empty? ? "codex" : (!claude.empty? ? "claude" : nil); session=!codex.empty? ? codex : (!claude.empty? ? claude : nil); Bridge.arm_guided(session, intent_id: "<ID>", intent_dir: "<STORE>/<dir>", store: "<STORE>", name: "<name>", harness: harness, agent: "plastic-enforcer", thread: (!codex.empty? ? codex : nil))'
   # auto (lock + auto), then hand to plastic-auto:
   ruby -r ~/.plastic/scripts/lib/bridge -e \
     'codex=ENV["CODEX_THREAD_ID"].to_s.strip; claude=ENV["CLAUDE_CODE_SESSION_ID"].to_s.strip; harness=!codex.empty? ? "codex" : (!claude.empty? ? "claude" : nil); session=!codex.empty? ? codex : (!claude.empty? ? claude : nil); Bridge.arm_auto(session, intent_id: "<ID>", intent_dir: "<STORE>/<dir>", store: "<STORE>", name: "<name>", harness: harness, agent: "plastic-enforcer", thread: (!codex.empty? ? codex : nil))'
   ```
   Replace `<ID>`, `<STORE>` (`~/.plastic/projects/<slug>/store` or `~/.plastic/store`),
   `<dir>` (the `ID--slug` directory), and `<name>`.
4. **Dispatch What-stage discovery (under the lock).** Right after arming, when the intent
   was just activated in step 1 (on a resume that already has
   `resources/discovery--<slug>.md`, skip: discovery runs once per intent, at activation
   only), dispatch the `plastic-intent-discovery` agent (see the `plastic-intent-discovering`
   skill), now that this session owns the lock, deposit authorized as the owner session. Resolve its
   model explicitly and pass it at dispatch time (belt-and-braces): `read-config
   agents.models.plastic-intent-discovery --project <repo>`. The agent runs QMD discovery
   over the intent's `chain`/`sources` and deposits findings to
   `resources/discovery--<slug>.md` only; it never writes the intent file, so the
   lock-owner-only rule is untouched. This is advisory context for Why, not a gate: if
   discovery yields nothing, proceed to Why normally.

   **Skip the dispatch when there is nothing to discover.** Read the activating intent's
   `chain` and `sources` frontmatter fields before dispatching. When BOTH are empty there
   are no graph edges to follow, so do not dispatch the agent. Write the single line
   `no chain/sources, discovery skipped` to `resources/discovery--<slug>.md` in its place,
   then go to Why. One filled field is enough to run the pass as written above.

**Session id resolution (verbatim from `plastic-auto`).** The first argument is the session
id the bridge is keyed by: pass the hook stdin `session_id` when you have it; in the executable
snippets, a nonblank `CODEX_THREAD_ID` identifies Codex, otherwise a nonblank
`CLAUDE_CODE_SESSION_ID` identifies Claude, otherwise identity remains unknown. Never infer a
harness from an absent variable. Both arms call `resolve_session`, which
picks the first non-empty of: the explicit id you pass → `CLAUDE_CODE_SESSION_ID` → a
deterministic derived key (a hash of the store and intent id). It never returns nil, so the
lock is taken even when every session env var is empty; arming prints a one-line stderr
notice when it falls through to the derived key.

**What the lock IS.** Ownership is session-keyed and lease-based: arming writes a durable
`delivery.lock` file in the intent dir naming this session as owner, and the owner's hooks
refresh the file mtime on tool activity (the lease heartbeat). The /tmp bridge is only a
cache of that file; on any disagreement the lock file wins, so a wiped /tmp never strands
the owner. Idempotent re-arm: arming again with the same owner just refreshes the lock; it
is not an error to re-board an intent this session already owns. A failed arm raises with
a message naming the resolving `plastic-lock` verb (`status`, `reclaim`, or `fix`): follow
that message, never delete a lock file by hand.

## Confirm delivery state

Read `savepoint.md` and classify from the **last line** alone, then verify ONLY that line's
artifact is real (sentinel-aware via `Bridge.stage_file_present?`). On drift (the last line
disagrees with files on disk), rebuild the ledger from disk and note the correction. Do not
inline the rebuild; the `plastic-intent-savepoint` skill owns it:
```bash
ruby -r ~/.plastic/scripts/lib/bridge -e 'Bridge.rebuild_savepoint("<intent_dir>")'
```

## Report + ask "auto or guided?" ONCE

Report: the intent, the station it lands at (the matrix below), what is delivered, the next
step. Then ask the user **"auto or guided?"** — exactly ONCE, whatever station it lands at.
Never re-ask at a later station.

- **guided** → `arm_guided` (lock only); continue step by step with the user through the
  station's work below.
- **auto** → `arm_auto` (lock + auto), then hand off to `plastic-auto`. The auto branch's
  only remaining job is the handoff; `plastic-auto` runs the cycle from here.

Read `../plastic-conventions/references/tiers-and-dispatch.md` for tier sizing and the
stage-to-agent dispatch rules behind the auto branch above.

## Board at the latest delivered station

The station is derived from `savepoint.md` last line + real artifacts on disk. See
`references/boarding-matrix.md` for the full table (last line → latest delivered → boards at →
continue with) and the per-station notes. Summary of what "continue" means per station:

Read `../plastic-conventions/references/gates-and-enforcement.md` for the transition-gate
mechanics, the audited escape, and gate logging that govern moving between the stations below.

- **What** → do what What requires (106-expanded), then brainstorm → `spec.md`.
- **Why** → continue brainstorming → `spec.md`.
- **How** → continue `plan.md` + `actions/` + `checklist.md`.
- **Exec** → verify what has been delivered, then continue (or restart) the delivery /
  research; tick the checklist.
- **ready to complete** (`Exec outcome.md created`) → exit at Done.
- **Done** → report only, ask what is next, never reopen.

## Disarm / release on done

When delivery finishes, disarm and release per the `plastic-auto` disarm/release prose (do
not duplicate it here). The guided branch releases the lock via `disarm_auto`, which is
mode-agnostic (it sets `auto = false` and calls `Worktree.release`), so it releases a guided
lock too. When the work ships through a release, the release path merges the branch before the
worktree is removed; the plain disarm remove is only for the no-release case.

## References

- `references/boarding-matrix.md` — the full boarding table and per-station behaviour.
