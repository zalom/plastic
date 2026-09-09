# ACTION_5: Rewrite test/doctor_done_signals_test.rb for the new check shapes

Depends on ACTION_1 and ACTION_2 landing (the `bookend_amnesty:` keyword no longer exists on
`Doctor.new` once ACTION_2 lands, which is the forcing function for every rewrite below).

## 1. Helpers (lines 29-33)
Replace:
```ruby
def doctor(bookend_amnesty: {}) = Doctor.new(plastic_home: @home, bookend_amnesty: bookend_amnesty)

def check(name, bookend_amnesty: {})
  doctor(bookend_amnesty: bookend_amnesty).check_done_signals.find { |c| c[:name] == name }
end
```
with:
```ruby
def doctor = Doctor.new(plastic_home: @home)

def check(name) = doctor.check_done_signals.find { |c| c[:name] == name }
```

## 2. `test_pass_when_terminal_intent_is_fully_reconciled` (lines 70-79)
Add one assertion for the new check (fully reconciled means no operational gap either):
```ruby
assert_equal "pass", check("savepoint_operational")[:status]
```
Everything else in this test stays as-is.

## 3. `test_gap_when_terminal_but_outcome_placeholder` (lines 98-109)
Rename to `test_legacy_note_when_terminal_but_outcome_placeholder`. Rewrite body:
```ruby
def test_legacy_note_when_terminal_but_outcome_placeholder
  write_index("13", section: "Abandoned")
  write_intent_dir("13")
  write_placeholder_outcome("13")
  write_savepoint_done("13", disposition: "abandoned")

  assert_equal "pass", check("signals_agree")[:status], "not a hard conflict"
  complete = check("signals_complete")
  assert_equal "pass", complete[:status], "outcome-missing is informational only, never warn"
  refute complete[:fixable], "there is no legitimate fix for a delivery-claim gap"
  assert(complete[:details].any? { |d| d.include?("still a placeholder") })
end
```

## 4. `test_gap_when_terminal_but_outcome_missing` (lines 112-121)
Rename to `test_legacy_note_when_terminal_but_outcome_missing`. Rewrite body:
```ruby
def test_legacy_note_when_terminal_but_outcome_missing
  write_index("14", section: "Completed")
  write_intent_dir("14")
  write_savepoint_done("14")

  assert_equal "pass", check("signals_agree")[:status]
  complete = check("signals_complete")
  assert_equal "pass", complete[:status]
  assert(complete[:details].any? { |d| d.include?("missing") })
end
```

## 5. `test_gap_when_terminal_but_savepoint_echo_missing` (lines 125-136)
Rename to `test_operational_gap_when_terminal_but_savepoint_echo_missing`. Rewrite body to check
`savepoint_operational` instead of `signals_complete`, and confirm `signals_complete` stays clean
since there is no outcome gap here:
```ruby
def test_operational_gap_when_terminal_but_savepoint_echo_missing
  write_index("17", section: "Completed")
  write_intent_dir("17")
  write_outcome("17")
  File.write(File.join(intent_dir("17"), "savepoint.md"),
             "2026-07-03T00:00:00Z  Exec  started\n")

  assert_equal "pass", check("signals_agree")[:status]
  assert_equal "pass", check("signals_complete")[:status], "no outcome gap here"
  operational = check("savepoint_operational")
  assert_equal "warn", operational[:status]
  assert operational[:fixable]
  assert_includes operational[:fix_hint], "rebuild-savepoint"
  assert(operational[:details].any? { |d| d.include?("no `Done delivered|abandoned` line") })
end
```

## 6. New test: savepoint.md missing entirely (previously uncovered)
Insert immediately after the rewritten test above:
```ruby
def test_operational_gap_when_terminal_but_savepoint_missing_entirely
  write_index("18", section: "Completed")
  dir = write_intent_dir("18")
  write_outcome("18")
  refute File.exist?(File.join(dir, "savepoint.md"))

  operational = check("savepoint_operational")
  assert_equal "warn", operational[:status]
  assert(operational[:details].any? { |d| d.include?("missing entirely") })
end
```

## 7. `test_savepoint_truthful_grandfathers_amnestied_terminal_phantom` (lines 221-234)
Rename to `test_savepoint_truthful_never_suppresses_terminal_phantom`. Rewrite body: the
suppression axis no longer exists, so this now proves the generic replacement (always report,
never suppress) directly, with no `bookend_amnesty:` parameter anywhere:
```ruby
def test_savepoint_truthful_never_suppresses_terminal_phantom
  write_index("23", section: "Completed")
  dir = write_intent_dir("23")
  write_outcome("23")
  File.write(File.join(dir, "savepoint.md"),
             "2026-07-03T00:00:00Z  Why  spec.md created\n2026-07-03T00:01:00Z  Why  spec.md created\n")

  # No amnesty mechanism exists anymore: every terminal phantom warns, unconditionally.
  assert_equal "warn", check("savepoint_truthful")[:status]
end
```

## 8. `test_no_audit_echo_gap_for_allowlisted_legacy_intent` (lines 238-247)
Rename to `test_savepoint_operational_warns_for_any_terminal_missing_echo`. Rewrite body to
check `savepoint_operational` (not `signals_complete`) and drop the `bookend_amnesty:` argument
entirely, proving the generic predicate warns unconditionally where the old mechanism used to
allowlist:
```ruby
def test_savepoint_operational_warns_for_any_terminal_missing_echo
  write_index("30", section: "Completed")
  write_intent_dir("30")
  write_outcome("30")
  File.write(File.join(intent_dir("30"), "savepoint.md"),
             "2026-07-03T00:00:00Z  Exec  started\n")

  operational = check("savepoint_operational")
  assert_equal "warn", operational[:status], "no allowlist exists anymore to suppress this"
end
```

## 9. Delete two now-redundant tests
Delete `test_audit_echo_gap_still_warns_when_not_allowlisted` (lines 251-261) and
`test_audit_echo_gap_still_warns_when_id_matches_but_scope_does_not` (lines 266-276) outright:
both existed only to pin "still warns when NOT on the allowlist," which is now the ONLY possible
behavior (item 8 above already covers "warns" for the generic case; there is no scope-qualified
allowlist axis left to test).

## 10. `test_extraction_preserves_both_gaps_when_a_dir_has_outcome_and_echo_gaps_together`
(lines 284-298)
Keep the test's intent (both gap conditions fire independently for the same dir) but split the
assertion across the two new check names, since the two conditions now land in different
`details` arrays rather than one:
```ruby
def test_extraction_preserves_both_gaps_when_a_dir_has_outcome_and_echo_gaps_together
  write_index("33", section: "Completed")
  write_intent_dir("33")
  File.write(File.join(intent_dir("33"), "savepoint.md"),
             "2026-07-03T00:00:00Z  Exec  started\n")

  complete = check("signals_complete")
  operational = check("savepoint_operational")
  assert_equal "pass", complete[:status]
  assert_equal "warn", operational[:status]
  assert(complete[:details].any? { |d| d.include?("33") && d.include?("outcome.md is missing") })
  assert(operational[:details].any? { |d| d.include?("33") && d.include?("no `Done delivered|abandoned` line") })
end
```

## Verification for this action
- `ruby test/doctor_done_signals_test.rb` (Minitest) is fully green.
- `grep -n "bookend_amnesty" test/doctor_done_signals_test.rb` returns zero matches.
- Test count: 5 renamed, 1 new (`test_operational_gap_when_terminal_but_savepoint_missing_
  entirely`), 2 deleted, net test count decreases by 1 from the pre-action file.
