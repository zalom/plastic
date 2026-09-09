# ACTION_2 - project-links: report a malformed/unresolvable Links line instead of silent-dropping it

Covers spec.md AC: "`project-links` reports an unresolvable `## Links` line as a
malformed-orphan candidate instead of silently dropping it, with a test built on a fixture
unresolvable line proving the tool produces a finding rather than an empty result."

**What does NOT change:** the written file's content. Owner ruling (intent file Insights,
2026-07-14 verified note) is explicit: "those three 3b lines are genuinely junk and SHOULD
drop... reprojection destroys nothing... the bug is the SILENCE, not the deletion." So this
action adds VISIBILITY only; a line that resolves to nothing is still absent from the
regenerated `## Links` section. Discovery citation: `scripts/project-links:202-219`
(`orphan_split`), the `next if label.nil?` branch that discards a dead ref with no trace
anywhere (not even the audit).

File: `scripts/project-links` (inside the worktree).

## 2a. `orphan_split` gains a third bucket: `dead`

Current (`scripts/project-links:202-219`):
```ruby
  def orphan_split(old_text, canonical_text, referer_store, store_index, node_index)
    canonical_targets = LinksProjection.parse_entries(canonical_text).map { |e| e[:target] }
    kept = []
    dropped_optin = []
    LinksProjection.parse_entries(old_text).each do |oe|
      next if canonical_targets.include?(oe[:target]) # already backed; not an orphan

      label = resolve_orphan_label(oe[:target], referer_store, store_index, node_index)
      next if label.nil? # dead: not backed AND does not resolve; silent drop, as before

      if drop_unbacked_links
        dropped_optin << oe
      else
        kept << { target: oe[:target], label: label }
      end
    end
    [kept, dropped_optin]
  end
```

Target:
```ruby
  def orphan_split(old_text, canonical_text, referer_store, store_index, node_index)
    canonical_targets = LinksProjection.parse_entries(canonical_text).map { |e| e[:target] }
    kept = []
    dropped_optin = []
    dead = []
    LinksProjection.parse_entries(old_text).each do |oe|
      next if canonical_targets.include?(oe[:target]) # already backed; not an orphan

      label = resolve_orphan_label(oe[:target], referer_store, store_index, node_index)
      if label.nil?
        # Resolves to nothing: still dropped from the file (nothing real to preserve),
        # but no longer silent. Reported as a malformed-orphan candidate in the audit.
        dead << { target: oe[:target] }
        next
      end

      if drop_unbacked_links
        dropped_optin << oe
      else
        kept << { target: oe[:target], label: label }
      end
    end
    [kept, dropped_optin, dead]
  end
```

## 2b. `project_store`: thread `dead` through the entries array

Current call site (`scripts/project-links:167-188`):
```ruby
        kept, dropped_optin = orphan_split(old_text, canonical_text, referer_store,
                                            store_index, node_index)
```
and the two `entries <<` calls in the same method (`:174-176`, `:180-182`, `:187-188`) each
carry `orphans_preserved:`/`orphans_dropped_optin:` keys.

Target: change the destructure to `kept, dropped_optin, dead = orphan_split(...)` and add
`orphans_dead: dead` to EVERY `entries <<` hash in `project_store` (the `:failed` early-return
hash too, with `orphans_dead: []`, so every entry has the key uniformly and the audit renderer
never has to guard against a missing key).

## 2c. Audit rendering: a new "malformed/dead references" section

In `render_audit` (`scripts/project-links:265-338`), alongside the existing
`preserved`/`dropped_optin` blocks (around line 308-322), add a third block using the same
shape:
```ruby
      dead_refs = res[:entries].flat_map { |e| Array(e[:orphans_dead]).map { |o| [e[:id], o] } }
      unless dead_refs.empty?
        lines << "### Malformed references found, dropped silently before this fix (#{dead_refs.size})"
        lines << "Resolve to no real intent under any known store; these are dropped from the " \
                 "regenerated ## Links section (nothing real to preserve), but were previously " \
                 "invisible to every check. Confirm each is genuinely dead (a typo'd slug, a " \
                 "sibling wrongly linked) rather than a missing store/relocation before trusting."
        dead_refs.each { |id, o| lines << "- #{id}: -> #{o[:target]}" }
        lines << ""
      end
```
Also add `dead_refs.size` to the totals line (the `lines << "Totals across all stores: ..."`
block around line 277-281): append `", malformed references found: #{total_dead}"` where
`total_dead = store_list.sum { |s| results[s[:key]][:entries].sum { |e| Array(e[:orphans_dead]).size } }`.

## 2d. `any_failed?` is unaffected

`dead` entries are a normal, successful projection outcome (the file still projects and
writes correctly); they are NOT `:failed` status. No change to `any_failed?` or the exit-code
logic (`scripts/project-links:349-351`, `:383`).

## 2e. Tests - `test/project_links_test.rb`

Add a fixture intent whose `## Links` carries a genuinely unresolvable single-dash line,
mirroring the real dealintell 3b shape the discovery documents
(`3d-payments-subscription-gating`, single dash, vs. the real `3d--payments-subscription-gating`
directory):

```ruby
def test_unresolvable_link_line_is_reported_not_silently_dropped
  write_intent(File.join(@home, "projects", "plastic", "store"), "20--parent",
               id: "20", intent: "Parent", sources: [], chain: [],
               links: "## Links\n- [[does-not-exist-anywhere|Ghost]]\n")

  tool = ProjectLinks.new(plastic_home: @home, audit_path: @audit)
  tool.run

  # The dead line does not survive into the regenerated file (still dropped).
  refute_includes read("projects/plastic/store/20--parent/20--parent.md"), "does-not-exist-anywhere"

  # But it IS reported in the audit as a finding, not silently absent.
  audit = File.read(@audit)
  assert_includes audit, "Malformed references found"
  assert_includes audit, "does-not-exist-anywhere"
end

def test_empty_output_on_nonempty_dead_input_would_be_a_failure
  # Falsifiable-check doctrine (208): prove the audit's dead-refs section is not
  # merely ALWAYS empty (which would make the assertion above vacuous). A store
  # with zero dead refs must emit no "Malformed references found" heading at all.
  run_tool
  refute_includes File.read(@audit), "Malformed references found",
    "a clean fixture store must not spuriously report dead refs"
end
```

The second test is the required falsifiable-check proof (per the dispatch brief's CI doctrine:
empty-output-on-nonempty-input counts as failure): it demonstrates the new section is
conditionally rendered, not a static string always present, so the first test's assertion
actually exercises new logic.

## Verify

`ruby -Itest test/project_links_test.rb` green, then the full suite.
