# ACTION_11 - doctor --fix-all documented as a router; doctor gains no write path

Covers spec.md AC: "Doctor's `--fix-all` behavior is documented as dispatching each fixable
finding to the named maintenance tool (`project-links`, `rebuild-graph`, `restore-intent-v1`,
or the curator); doctor itself gains no `--apply` or `--fix` mutation code path."

Depends on ACTION_9 (`scripts/maintenance-run` exists, so the routing table can name it).

**Confirmed today: no `--fix-all` flag exists anywhere** (`grep -rn "fix-all\|fix_all"
scripts/ skills/ PLASTIC.md PLASTIC-reference.md` returns nothing). What DOES exist is
`skills/doctor/SKILL.md`'s Step 4/5 "Fix all / Select individually / Skip" prompt, which is
already the router this AC asks doctor to be documented as: **no `doctor.rb` code changes in
this action.** This action (a) documents that the existing "Fix all" prompt IS the "doctor
--fix-all" concept the spec names, and (b) closes a real routing gap in Step 5's table: the
`graph_links_projection` fix_hint (`scripts/doctor.rb:812-818`) has NO matching row in Step
5's table today (checked: the table's patterns are chmod/mkdir/INDEX/frontmatter/provision/
reinstall/curator-revisions only), so an agent hitting that fixable warning today has no
documented action to take. This action adds that row.

Files: `skills/doctor/SKILL.md`, `scripts/doctor.rb` (fix_hint text only, no logic change)
(both inside the worktree).

## 11a. `skills/doctor/SKILL.md` - name "Fix all" as the router, add the missing row

In Step 4 ("Offer fixes"), after the existing "If no fixable issues exist, skip this step."
line, add:
```

This "Fix all / Select individually / Skip" prompt IS the router the spec calls
`doctor --fix-all` (intent 197): doctor itself never mutates anything (see Step 5's table and
"Important Notes" below); "Fix all" means "dispatch every fixable finding to the maintenance
tool or skill that owns that class of repair," one row per fix_hint pattern.
```

In Step 5's table (`skills/doctor/SKILL.md`, the `| Fix hint pattern | Agent action |` table),
add one new row, in the same position order as the fix_hint text it matches
(`graph_links_projection`'s fix_hint, `scripts/doctor.rb:814-818`):
```
| "Run scripts/project-links ... PRESERVES ... --drop-unbacked-links" | Run `ruby ~/.plastic/scripts/maintenance-run --tool project-links --intent <id> --apply` for the one flagged id (never run bare `project-links` against a real store outside the rare owner-approved batch exception, D2) |
```

## 11b. `scripts/doctor.rb` - minor fix_hint addition (no logic change)

Current `graph_links_projection` fix_hint (`scripts/doctor.rb:814-818`):
```ruby
      "Run scripts/project-links to regenerate the canonical ## Links sections. By default " \
      "it PRESERVES any line unbacked by frontmatter that still resolves to a real intent " \
      "(reported as an orphan candidate, never silently deleted); add the missing " \
      "sources/chain edge if the relationship is real, or pass --drop-unbacked-links to " \
      "delete an orphan candidate deliberately."
```

Target (appends one sentence; keeps every existing substring the current test asserts on -
`--drop-unbacked-links` and `PRESERVES` both still appear verbatim, so
`test/doctor_links_projection_test.rb:166-178` keeps passing unmodified):
```ruby
      "Run scripts/project-links to regenerate the canonical ## Links sections. By default " \
      "it PRESERVES any line unbacked by frontmatter that still resolves to a real intent " \
      "(reported as an orphan candidate, never silently deleted); add the missing " \
      "sources/chain edge if the relationship is real, or pass --drop-unbacked-links to " \
      "delete an orphan candidate deliberately. Prefer `ruby scripts/maintenance-run --tool " \
      "project-links --intent <id> --apply` over running project-links directly: it detects " \
      "(never acquires) the target's delivery lock, requires a clean store working tree, and " \
      "commits the scoped change plus its revisions.md receipt as one merged operation " \
      "(PLASTIC.md > WORK vs MAINTENANCE)."
```

## 11c. Tests

No new test file needed. Confirm the existing assertions still hold (they are substring
checks on the fix_hint, unaffected by the appended sentence):
`ruby -Itest test/doctor_links_projection_test.rb` - specifically
`test_fix_hint_names_the_preserving_default_and_the_opt_in_flag` must stay green.

Add one new assertion to that same test proving the new sentence landed (drift-proofing this
action itself):
```ruby
def test_fix_hint_names_maintenance_run
  seed_targets
  write_intent(plastic_store, "5--child", id: "5", intent: "Child",
               sources: ["40"], chain: [],
               links: "## Links\n<!-- Retroactive (intent 60b): heading only. -->\n")

  check = links_check
  assert_includes check[:fix_hint], "maintenance-run"
end
```
(Reuses this test file's own `seed_targets`/`write_intent`/`links_check` helpers - read them
first, do not redefine.)

## Verify

`ruby -Itest test/doctor_links_projection_test.rb` green (both the pre-existing and the new
assertion), then the full suite. No change anywhere makes doctor.rb write, execute, or shell
out to anything; it remains detection-only (confirmed: no `system`/`Open3`/`File.write` calls
are added to `doctor.rb` by this action).
