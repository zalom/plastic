# ACTION_1: Generic repairability predicate in doctor.rb

Target: `scripts/doctor.rb`. Replaces the id-list-suppressed `signals_complete` with a
repairability-classified pair of checks, computed at runtime from file presence only.

## 1. `done_signal_findings_for_dir` (currently `scripts/doctor.rb:676-741`)

Keep the method's existing signature exactly as-is (`dir, label:, scope:, dirname:, terminal:,
active:`) - `scope:` stays even though this method no longer reads `@bookend_amnesty`, because
222's `check_intent_end` calls this same method and its call site must not need to change.

Replace the body's amnesty-consulting parts:

```ruby
def done_signal_findings_for_dir(dir, label:, scope:, dirname:, terminal:, active:)
  outcome = File.join(dir, "outcome.md")
  outcome_real = Bridge.stage_file_present?(outcome)
  findings = { conflict: nil, phantom: nil, gap: [], operational_gap: [], stalled: nil }

  if active && outcome_real
    findings[:conflict] = "#{label}: outcome.md is real but the intent is still under ## Active " \
                          "(INDEX is canonical - move it to its terminal section or revert outcome.md)"
  end

  # Savepoint truthfulness (advisory, never fail; intent 134). Terminal phantom lines are
  # ALWAYS report-only (immutable history), with no suppression by id or scope (intent 211:
  # the generic replacement for the frozen 170a amnesty list is simply "never suppress" -
  # the message already labels a terminal phantom report-only, so dropping the id-based
  # suppression is strictly more general and needs no per-store state at all).
  phantom_lines = Bridge.savepoint_phantom_lines(dir)
  if phantom_lines.any?
    detail = phantom_lines.map { |line, reason| "#{line} (#{reason})" }.join("; ")
    scope_note = terminal ? "terminal in INDEX, report-only (immutable history)" : "live intent, auto-rebuildable"
    findings[:phantom] = "#{label}: #{phantom_lines.size} phantom savepoint line(s) contradicted by " \
                         "disk, #{scope_note}: #{detail}"
  end

  # Delivery-claim gap (intent 211, 219 D6): a missing/placeholder outcome.md on a terminal
  # intent is never fabricated, so this is unrepairable by construction. Reported informational
  # only (signals_complete, always status "pass" - see check_done_signals).
  if terminal && !outcome_real
    state = File.exist?(outcome) ? "still a placeholder" : "missing"
    findings[:gap] << "#{label}: terminal in INDEX but outcome.md is #{state} " \
                     "(delivery claim - never fabricated)"
  end

  if terminal
    # Operational gap (intent 211, 219 D6): savepoint.md missing entirely (not previously
    # checked at all) or present but missing the Done bookend - both are minimally
    # reconstructible via maintenance-run --tool rebuild-savepoint, so this is repairable and
    # reported as a fixable warn (savepoint_operational).
    savepoint = File.join(dir, "savepoint.md")
    if !File.exist?(savepoint)
      findings[:operational_gap] << "#{label}: terminal in INDEX but savepoint.md is missing " \
                                    "entirely (operational - reconstructible)"
    elsif File.read(savepoint) !~ /\bDone\b.*\b(delivered|abandoned)\b/
      findings[:operational_gap] << "#{label}: terminal in INDEX but savepoint.md has no " \
                                    "`Done delivered|abandoned` line (operational - reconstructible)"
    end

    # Stalled completion: unchanged, never consulted amnesty.
    if File.exist?(Lock.path(dir))
      note = Lock.fresh?(dir) ? "delivery.lock still present (post-done window not closed)"
                              : "delivery.lock is present and STALE"
      findings[:stalled] = "#{label}: #{note} - the End tail did not finish"
    end
  end

  findings
end
```

Delete the old `phantom_amnestied`/`amnestied` lines and their surrounding comment blocks
entirely (no trace of `@bookend_amnesty` left in this method).

## 2. `check_done_signals` (currently `scripts/doctor.rb:743-846`)

Replace the collection loop and the checks it builds:

```ruby
def check_done_signals(scopes: nil)
  conflicts = []
  gaps = []              # delivery-claim (outcome.md) gaps only - legacy, informational
  operational_gaps = []  # savepoint gaps (missing file, or missing Done echo) - repairable
  stalled = []
  phantoms = []

  done_signal_stores(scopes).each do |store|
    index_sections_by_dir(store[:index]).each do |dirname, in_sections|
      dir = File.join(store[:store_dir], dirname)
      next unless File.directory?(dir)

      terminal = (in_sections & ["Completed", "Abandoned"]).any?
      active = in_sections.include?("Active") && !terminal
      label = "#{store[:scope]} store/#{dirname}"

      findings = done_signal_findings_for_dir(
        dir, label: label, scope: store[:scope], dirname: dirname, terminal: terminal, active: active
      )
      conflicts << findings[:conflict] if findings[:conflict]
      phantoms << findings[:phantom] if findings[:phantom]
      gaps.concat(findings[:gap])
      operational_gaps.concat(findings[:operational_gap])
      stalled << findings[:stalled] if findings[:stalled]
    end
  end

  checks = []

  # signals_agree: unchanged.
  if conflicts.empty?
    checks << check(
      category: "done_signals", name: "signals_agree", status: "pass",
      message: "No done-signal conflicts (no intent has a real outcome.md while still Active)"
    )
  else
    checks << check(
      category: "done_signals", name: "signals_agree", status: "fail",
      message: "#{conflicts.size} done-signal conflict#{conflicts.size == 1 ? "" : "s"} " \
               "(INDEX ## Completed/## Abandoned is canonical; a real outcome.md must not stay Active)",
      details: conflicts, fixable: true,
      fix_hint: "Reconcile to INDEX (canonical): move the intent to its terminal section, or revert " \
                "outcome.md to a placeholder. Deliverable-exists but still-Active is the one done-signal " \
                "state that must never persist."
    )
  end

  # signals_complete (intent 211, 219 D6, repurposed): outcome.md delivery-claim gaps only.
  # Never fabricated, so there is no legitimate fix to hint at - always status "pass",
  # informational (matches check_skill_lint's advisory precedent: count + details, no
  # fix_hint/fixable, never affects doctor's exit code).
  if gaps.empty?
    checks << check(
      category: "done_signals", name: "signals_complete", status: "pass",
      message: "Every terminal intent carries a real outcome.md"
    )
  else
    checks << check(
      category: "done_signals", name: "signals_complete", status: "pass",
      message: "#{gaps.size} terminal intent#{gaps.size == 1 ? "" : "s"} missing a real outcome.md " \
               "(delivery claim - never fabricated; informational only, does not affect doctor's exit code)",
      details: gaps
    )
  end

  # savepoint_operational (intent 211, NEW): missing savepoint.md or missing Done echo -
  # repairable via maintenance-run --tool rebuild-savepoint, so this stays warn+fixable.
  if operational_gaps.empty?
    checks << check(
      category: "done_signals", name: "savepoint_operational", status: "pass",
      message: "No terminal intent is missing an operational savepoint.md or its Done echo"
    )
  else
    checks << check(
      category: "done_signals", name: "savepoint_operational", status: "warn",
      message: "#{operational_gaps.size} terminal intent#{operational_gaps.size == 1 ? "" : "s"} " \
               "missing an operational savepoint.md or its Done echo (reconstructible)",
      details: operational_gaps, fixable: true,
      fix_hint: "Reconstruct the minimal two-line started/Done echo via " \
                "`maintenance-run --tool rebuild-savepoint --intent <id> --apply` (197-conformant: " \
                "receipt-before-write via RevisionsWriter, one intent per invocation, owner-approval-gated)."
    )
  end

  if stalled.empty?
    checks << check(
      category: "done_signals", name: "stalled_completion", status: "pass",
      message: "No stalled completions (every terminal intent released its delivery lock)"
    )
  else
    checks << check(
      category: "done_signals", name: "stalled_completion", status: "warn",
      message: "#{stalled.size} stalled completion#{stalled.size == 1 ? "" : "s"} " \
               "(terminal in INDEX but the End tail did not finish)",
      details: stalled, fixable: true,
      fix_hint: "Finish the End tail via stale-lock reclaim: run /plastic-doctor reclaim the lock, " \
                "then complete the tail (Worktree.release -> Lock.release -> purge -> QMD reindex " \
                "last). This FINISHES a completion; it is NOT a reactivation of a done intent."
    )
  end

  # savepoint_truthful: advisory only (intent 134), never fails. No amnesty suppression left.
  if phantoms.empty?
    checks << check(
      category: "done_signals", name: "savepoint_truthful", status: "pass",
      message: "No savepoint.md lines are contradicted by disk (phantom-line check clean)"
    )
  else
    checks << check(
      category: "done_signals", name: "savepoint_truthful", status: "warn",
      message: "#{phantoms.size} intent#{phantoms.size == 1 ? "" : "s"} carry savepoint.md " \
               "line(s) contradicted by disk (advisory; terminal history stays report-only)",
      details: phantoms, fixable: true,
      fix_hint: "For a live (Active) intent, run plastic-intent-savepoint to rebuild via " \
                "Bridge.rebuild_savepoint. Terminal (Completed/Abandoned) intents are immutable: " \
                "a phantom there stays advisory unless an explicit human grant authorizes the " \
                "124a manual Done-bookend repair."
    )
  end

  checks
end
```

## Verification for this action
- Every existing call site of `check_done_signals`/`done_signal_findings_for_dir` (run_checks,
  `doctor --store`, 222's `check_intent_end`) still compiles with no signature change beyond the
  new `operational_gap:` hash key, which callers that do not read it can ignore.
- `grep -n "@bookend_amnesty" scripts/doctor.rb` returns zero matches after this action (the
  ivar is fully retired here; the constructor's own declaration is removed in ACTION_2, so this
  action alone leaves the ivar referenced nowhere but still assignable - ACTION_2 must land in
  the same delivery, per plan.md's ordering note, or `doctor.rb` still loads but the parameter is
  simply unused dead weight until ACTION_2 removes it).
