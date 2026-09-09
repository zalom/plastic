# ACTION_1 - project-links: add a single-intent scope flag

Covers spec.md AC: "`project-links` accepts a single-intent scope flag (for example
`--intent <id>`) that regenerates exactly one intent's `## Links` section and leaves every
other intent's file untouched, with a test proving no other intent's file changes."

File: `scripts/project-links` (inside the worktree). Discovery citation: the whole file has
zero per-intent scoping today (discovery.md section 2); `run` always iterates every store and
every node (`scripts/project-links:114-144`).

**Load-bearing correctness finding, verified live against the real store today (not
hypothetical): bare intent ids COLLIDE across stores.** `find ~/.plastic -maxdepth 4 -type d
-name "26--*"` matches THREE different intents (`store/26--ai-agents-resources` (global),
`projects/mihradesign/store/26--fix-cross-user-cart-adoption-leak`,
`projects/plastic/store/26--channel-aware-update-notification`); `-name "15--*"` matches FOUR
(`projects/dealintell/store/15--...`, two more in mihradesign and plastic, plus a stale
`.worktrees/` copy). Both `26` and `15` are proof-case targets for this very intent (Task 13).
A naive `--intent <id>` that matches "any store containing this id" would silently regenerate
and WRITE to the wrong intent in a DIFFERENT project's store - the exact silent-mistake class
this whole intent exists to eliminate. The scope flag MUST resolve to exactly one directory
store-wide, aborting loud on ambiguity (mirroring `scripts/restore-intent-v1`'s own
`find_intent_dir`, `scripts/restore-intent-v1:219-238`, which already solves this identical
problem the same way), never silently picking the first match.

## 1a. `ProjectLinks.new` gains `intent:` and `store:` keywords

Current constructor (`scripts/project-links:49-69`):
```ruby
  def initialize(plastic_home: DEFAULT_HOME, dry_run: false, audit_path: nil,
                 drop_unbacked_links: false)
    @plastic_home = plastic_home
    @dry_run = dry_run
    @drop_unbacked_links = drop_unbacked_links
```

Target: add `intent: nil, store: nil` to the signature and `@intent = intent && intent.to_s`,
`@store = store` to the body. `store:` is the OPTIONAL disambiguator (a `key` value from
`StoreDiscovery`, e.g. `"global"` or `"project:dealintell"`) used only when `intent` alone is
ambiguous. Add `attr_reader :intent, :store` alongside the existing `attr_reader
:plastic_home, :dry_run, :audit_path, :drop_unbacked_links` (line 71).

## 1b. `run` resolves the one target store for `intent`, aborting loud on ambiguity

Current (`scripts/project-links:114-144`), the loop that builds `nodes_by_store`, is
UNCHANGED (every store's nodes are still loaded, because `store_index`/`node_index` must stay
whole-store: every OTHER intent must still resolve correctly against the target's own
sources/chain, and the target's own resolvable label must still be found by other intents'
orphan checks - only the set of nodes actually **projected and written** narrows). After that
loop (still inside `run`, before the `results = {}` block at `scripts/project-links:133-140`),
insert the resolution step, then use it to scope which store(s) actually call `project_store`
with a real `only:`:

```ruby
    target_store_key = intent ? resolve_target_store(store_list, nodes_by_store, intent) : nil

    results = {}
    store_list.each do |s|
      key = s[:key]
      if intent
        results[key] = (key == target_store_key) ? project_store(
          key, nodes_by_store[key],
          relocation_map: relocation_map, store_index: store_index, node_index: node_index,
          only: intent
        ) : { entries: [], counts: Hash.new(0) }
      else
        results[key] = project_store(
          key, nodes_by_store[key],
          relocation_map: relocation_map, store_index: store_index, node_index: node_index
        )
      end
    end
```

New private method, placed near `orphan_split`:
```ruby
  # Resolves --intent to exactly ONE store key, aborting loud on ambiguity (mirrors
  # scripts/restore-intent-v1's find_intent_dir, which solves this identical cross-store
  # id-collision problem the same way). `store:` (explicit --store) short-circuits resolution
  # when the caller already knows which store; otherwise every store containing a matching
  # id is a candidate, and more than one is a hard abort (never silently pick one).
  def resolve_target_store(store_list, nodes_by_store, intent)
    if store
      abort "project-links: --store #{store.inspect} has no intent #{intent.inspect}" \
        unless nodes_by_store[store]&.key?(intent)
      return store
    end

    candidates = store_list.select { |s| nodes_by_store[s[:key]].key?(intent) }.map { |s| s[:key] }
    abort "project-links: intent #{intent.inspect} not found in any known store" if candidates.empty?
    if candidates.length > 1
      abort "project-links: intent #{intent.inspect} is ambiguous across stores " \
            "(#{candidates.join(", ")}); pass --store <key> to disambiguate (e.g. --store " \
            "#{candidates.first})"
    end
    candidates.first
  end
```

## 1c. `project_store` gains `only:` and skips every non-matching id

Current signature and loop start (`scripts/project-links:149-151`):
```ruby
  def project_store(referer_store, nodes, relocation_map:, store_index:, node_index:)
    entries = []
    nodes.each do |id, node|
```

Target:
```ruby
  def project_store(referer_store, nodes, relocation_map:, store_index:, node_index:, only: nil)
    entries = []
    nodes.each do |id, node|
      next if only && id != only
```

Combined with 1b's store-level resolution, this is the whole scoping mechanism: `run` only
ever calls `project_store` with a real `only:` on the ONE store that actually contains the
target id (every other store gets a synthetic empty result, never even entering
`project_store`), and within that one store, `only:` skips every non-matching id. No other
`File.write` call exists in `project_store`, so this one guard is sufficient; nothing else in
the method touches disk per-node.

## 1d. Audit rendering: note the scope when `intent` is set

In `render_audit` (`scripts/project-links:265-270`), right after the `Generated:` line, add
(only when `intent` is present):
```ruby
    lines << "Scoped to intent #{intent} only (--intent)." if intent
    lines << ""
```
Cosmetic but load-bearing for a human reviewing the audit after a scoped run: without it the
totals line would look like a store-wide run found almost nothing changed, which reads as
suspicious rather than expected.

## 1e. CLI flag parsing

Current `if $PROGRAM_NAME == __FILE__` block (`scripts/project-links:354-384`): add
`intent = nil` and `store = nil` locals, `when "--intent" then intent = ARGV[i + 1]; i += 2`
and `when "--store" then store = ARGV[i + 1]; i += 2` cases, and pass `intent: intent, store:
store` into `ProjectLinks.new(...)`. Update the `abort` usage string (line 367-368) to list
`--intent <id> [--store <key>]` alongside the existing flags. Update the module doc comment's
`Usage:` line (line 25) the same way, and note there that `--store` only matters when `--intent`
alone is ambiguous (the tool aborts loud naming every candidate in that case).

## 1f. Tests - `test/project_links_test.rb`

Add (near the existing scoping-adjacent tests; the file already has a `build_fixture_stores`
helper per discovery's citation of `test/project_links_test.rb`):

```ruby
def test_intent_scope_regenerates_only_the_named_intent
  # build_fixture_stores (setup) already seeds "11--child" (project:plastic) with a
  # stale ## Links ("Retroactive (intent 60b): heading only.") against real sources
  # ["global:40"]/chain ["global:1a2"], and "12--grandchild" with NO ## Links at all
  # (also due to regenerate on an unscoped run). Scope to "11" only and confirm 12
  # (and every other fixture file) is untouched.
  before = Dir.glob(File.join(@home, "**", "*.md")).to_h { |f| [f, File.read(f)] }

  tool = ProjectLinks.new(plastic_home: @home, audit_path: @audit, intent: "11")
  tool.run

  before.each do |path, original|
    if path.end_with?("11--child/11--child.md")
      refute_equal original, File.read(path), "the scoped intent must be regenerated"
    else
      assert_equal original, File.read(path), "an unscoped intent must be byte-identical: #{path}"
    end
  end
end

def test_intent_scope_with_unknown_id_changes_nothing
  before = Dir.glob(File.join(@home, "**", "*.md")).to_h { |f| [f, File.read(f)] }
  tool = ProjectLinks.new(plastic_home: @home, audit_path: @audit, intent: "no-such-id")
  tool.run
  before.each { |path, original| assert_equal original, File.read(path) }
end

# FALSIFIABLE (208) and load-bearing: this is the EXACT real-world shape Task 13 depends
# on (ids 26 and 15 both collide across real stores today). A bare --intent matching more
# than one store must abort loud, listing every candidate, rather than silently write to
# the first match found.
def test_ambiguous_intent_across_stores_aborts_with_no_write
  knowdb = File.join(@home, "projects", "knowdb", "store")
  FileUtils.mkdir_p(knowdb)
  write_intent(knowdb, "13--knowdb-collision", id: "13", intent: "Unrelated knowdb thing",
               sources: [], chain: [])
  write_index(File.join(@home, "projects", "knowdb", "INDEX.md"))
  before = Dir.glob(File.join(@home, "**", "*.md")).to_h { |f| [f, File.read(f)] }

  _out, err = capture_subprocess_io do
    assert_raises(SystemExit) do
      ProjectLinks.new(plastic_home: @home, audit_path: @audit, intent: "13").run
    end
  end
  assert_match(/ambiguous/, err)
  assert_match(/--store/, err)

  before.each { |path, original| assert_equal original, File.read(path), "no file may change on an aborted ambiguous run" }
end

# The --store companion resolves the SAME ambiguity deliberately.
def test_explicit_store_disambiguates_and_scopes_correctly
  knowdb = File.join(@home, "projects", "knowdb", "store")
  FileUtils.mkdir_p(knowdb)
  write_intent(knowdb, "13--knowdb-collision", id: "13", intent: "Unrelated knowdb thing",
               sources: [], chain: [])
  write_index(File.join(@home, "projects", "knowdb", "INDEX.md"))
  knowdb_md = File.join(knowdb, "13--knowdb-collision", "13--knowdb-collision.md")
  before_knowdb = File.read(knowdb_md)

  results = ProjectLinks.new(plastic_home: @home, audit_path: @audit, intent: "13", store: "project:plastic").run

  assert_equal before_knowdb, File.read(knowdb_md), "the non-targeted store's same-id intent must be untouched"
  # Every OTHER store (including knowdb, which also has an id "13") must report a synthetic
  # zero-activity result, never having been handed to project_store at all.
  assert_equal 0, results["project:knowdb"][:entries].size
end
```

Note: `capture_subprocess_io` captures real subprocess stdout/stderr, not an in-process
`abort`'s stderr. Since these two new tests call `ProjectLinks` directly (in-process, not via
`Open3`/subprocess), use Minitest's `assert_output`/`capture_io` (captures `$stdout`/`$stderr`
from the CURRENT process) instead, matching whichever helper this test file's existing
in-process `abort` tests already use elsewhere in the suite (search
`test/restore_intent_v1_lib_test.rb` or similar for the project's own established
in-process-`abort`-capturing convention before choosing `capture_io` vs a `StringIO` swap).

## Falsifiable test proof

`test_intent_scope_with_unknown_id_changes_nothing` is the CI-doctrine falsifiable check
(208): an empty/no-op result on a real `--intent` run must be observably distinguishable from
"the flag silently did nothing" - the FIRST test (`_regenerates_only_the_named_intent`) proves
the flag does something when given a real, stale id; the second proves it does NOTHING beyond
that scope. Together they rule out both failure directions (flag is a no-op vs. flag is
actually store-wide in disguise).

## Verify

`ruby -Itest test/project_links_test.rb` green, then the full suite (see plan.md).
