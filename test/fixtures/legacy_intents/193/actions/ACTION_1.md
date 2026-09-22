# Action 1: Build restore-intent-v1, prove it against the real incident shape, document the procedure

Consolidated M-tier action carrying the whole ordered delivery for intent 193. Self-contained:
follow it top to bottom without needing `plan.md`. All paths are relative to the worktree root
`/Users/zlatko/apps/personal/plastic/.claude/worktrees/193--restore-to-v1-preserves-graph`
(branch `plastic/193--restore-to-v1-preserves-graph`). Use absolute paths in every command. Do
not touch the main checkout `/Users/zlatko/apps/personal/plastic` or any other worktree. Do not
edit `scripts/project-links`, `scripts/lib/links_projection.rb`, or `hooks/create-gate` (intent
192 owns them concurrently); call `scripts/project-links` as a subprocess only.

Ground truth already verified directly against `~/.plastic` git history (do not re-derive):
commit `aea4bfd` ("intent 124 delivered") is v1, `chain: []`; commit `8a8d505` (create intent
131, `sources: ["124"]`) correctly wrote `chain: [] -> ["131"]` into 124 (the I1 backlink);
commit `01a3911` amended 124's prose in place without touching frontmatter; commit `60a51bf`
("Restore intent 124 to v1") reverted the whole file, and in the same diff hunk swapped
`chain: ["131"]` for a hand-authored `chain: ["124a"]`, destroying the `131` edge. Note: v1
itself never carried a dangling edge (124a was created later, at `cde5bbe`, and is still a live
directory today); the target-resolution work in Task 1 is a general hardening, not a literal
replay of something the 124 incident itself proves. Do not write test names or comments that
claim otherwise.

---

## Task 1: Pure library `scripts/lib/restore_intent_v1.rb`

**Files:**
- Create: `scripts/lib/restore_intent_v1.rb`
- Test: `test/restore_intent_v1_lib_test.rb`

This module has NO file IO, NO git, NO `system` calls. It is pure: same inputs always produce
the same outputs. It reuses `GraphRebuild.resolve_ref` (from `scripts/lib/graph_rebuild.rb`) for
target existence and `FrontmatterWriter.rewrite_arrays` (from `scripts/lib/frontmatter_writer.rb`)
for the write. Both already exist; do not reimplement either.

- [ ] **Step 1: Write the failing tests**

```ruby
# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require_relative "../scripts/lib/restore_intent_v1"

class RestoreIntentV1LibTest < Minitest::Test
  # A minimal store_index/relocation_map: one store "global" holding ids "1" and "2".
  # "999" is absent from every known store (a confirmed-dead target).
  def store_index
    { "global" => %w[1 2] }
  end

  def empty_relocation_map
    {}
  end

  def test_union_dedupes_and_preserves_both_snapshots
    graph = RestoreIntentV1.compute_graph(
      v1_sources: [], v1_chain: ["1"],
      current_sources: [], current_chain: ["1", "2"],
      referer_store: "global", relocation_map: empty_relocation_map, store_index: store_index
    )
    assert_equal %w[1 2], graph[:chain].sort
    assert_empty graph[:dropped]
  end

  def test_dead_target_is_dropped_and_reported
    graph = RestoreIntentV1.compute_graph(
      v1_sources: [], v1_chain: ["999"],
      current_sources: [], current_chain: ["1"],
      referer_store: "global", relocation_map: empty_relocation_map, store_index: store_index
    )
    assert_equal ["1"], graph[:chain]
    refute_includes graph[:chain], "999"
    assert_equal [{ field: :chain, ref: "999" }], graph[:dropped]
  end

  def test_unknown_store_ref_is_kept_and_flagged_unverified
    graph = RestoreIntentV1.compute_graph(
      v1_sources: [], v1_chain: ["otherstore:5"],
      current_sources: [], current_chain: [],
      referer_store: "global", relocation_map: empty_relocation_map, store_index: store_index
    )
    assert_includes graph[:chain], "otherstore:5"
    assert_equal [{ field: :chain, ref: "otherstore:5" }], graph[:unverified]
    assert_empty graph[:dropped]
  end

  def test_apply_graph_rewrites_only_sources_and_chain
    v1_content = <<~MD
      ---
      id: "1"
      intent: "Example"
      sources: []
      chain: []
      created: 2026-01-01
      author: human
      tags: []
      ---

      ## Intent
      Example.
    MD
    result = RestoreIntentV1.apply_graph(v1_content, desired_sources: [], desired_chain: ["2"])
    assert_includes result, "chain: [\"2\"]"
    assert_includes result, "## Intent\nExample.\n"
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd /Users/zlatko/apps/personal/plastic/.claude/worktrees/193--restore-to-v1-preserves-graph && ruby -Itest test/restore_intent_v1_lib_test.rb`
Expected: FAIL/ERROR with "cannot load such file -- ../scripts/lib/restore_intent_v1" (the file does not exist yet).

- [ ] **Step 3: Write the implementation**

```ruby
# encoding: UTF-8
# frozen_string_literal: true

require_relative "graph_rebuild"
require_relative "frontmatter_writer"

# RestoreIntentV1 - pure graph math for restoring a completed intent's frontmatter
# graph across a v1 prose revert (intent 193). No file IO, no git, no `system`.
#
# The rule this module carries: prose reverts to v1; the sources/chain graph is
# APPEND-ONLY and is the UNION of the v1 snapshot and the current snapshot, never
# a re-derivation from other intents' reciprocal edges (that would silently erase
# legitimate I2-asymmetry edges doctor.rb never auto-fixes). Before the union is
# written, every edge (from either snapshot) is target-resolved by reusing
# GraphRebuild.resolve_ref verbatim, the same classifier rebuild-graph and
# doctor.rb already share: a :dead edge (resolves to no id in any known store) is
# dropped and reported; :same_store, :cross_store, and :unknown_store edges are
# all kept (bias toward preserving an edge that might be real; only positive proof
# of non-existence justifies a drop).
module RestoreIntentV1
  module_function

  # PURE. Computes the desired sources/chain for a restore.
  #
  # Returns:
  #   { sources: [...], chain: [...],
  #     dropped:    [ { field: :sources|:chain, ref: "<id or store:id>" }, ... ],
  #     unverified: [ { field: :sources|:chain, ref: "<id or store:id>" }, ... ] }
  def compute_graph(v1_sources:, v1_chain:, current_sources:, current_chain:,
                     referer_store:, relocation_map:, store_index:)
    sources_result = resolve_union(v1_sources, current_sources, :sources,
                                    referer_store, relocation_map, store_index)
    chain_result = resolve_union(v1_chain, current_chain, :chain,
                                  referer_store, relocation_map, store_index)

    {
      sources: sources_result[:kept],
      chain: chain_result[:kept],
      dropped: sources_result[:dropped] + chain_result[:dropped],
      unverified: sources_result[:unverified] + chain_result[:unverified],
    }
  end

  # PURE. Union two edge arrays (deduped, order-preserving, first array's order
  # wins for shared entries), then target-resolve each via GraphRebuild.resolve_ref.
  def resolve_union(v1_edges, current_edges, field, referer_store, relocation_map, store_index)
    union = (Array(v1_edges).map(&:to_s) + Array(current_edges).map(&:to_s)).uniq
    kept = []
    dropped = []
    unverified = []

    union.each do |ref|
      classification = GraphRebuild.resolve_ref(
        ref, referer_store: referer_store, relocation_map: relocation_map, store_index: store_index
      )
      case classification[:status]
      when :dead
        dropped << { field: field, ref: ref }
      when :unknown_store
        kept << ref
        unverified << { field: field, ref: ref }
      else # :same_store, :cross_store
        kept << ref
      end
    end

    { kept: kept, dropped: dropped, unverified: unverified }
  end

  # PURE. Reapply the computed graph onto v1's exact prose. Delegates entirely to
  # FrontmatterWriter; this module never rewrites YAML itself.
  def apply_graph(v1_content, desired_sources:, desired_chain:)
    FrontmatterWriter.rewrite_arrays(v1_content, sources: desired_sources, chain: desired_chain)
  end

  # PURE. Render one revisions.md entry (intent 107's append-only, move-and-record
  # convention). `n` is the next revision number for this intent's revisions.md.
  def render_revision_entry(n, at:, timestamp:, before_sources:, after_sources:,
                             before_chain:, after_chain:, dropped:)
    lines = []
    lines << "## Revision v#{n} - #{timestamp}"
    lines << "- Why: restore-to-v1 preserved the frontmatter graph across a completed-intent " \
             "restore [rule: restored-to-v1]"
    lines << "- Prior location: frontmatter - sources/chain; prose reverted to ref #{at}"
    lines << "- Change: sources (before: #{before_sources.inspect} -> after: #{after_sources.inspect}); " \
             "chain (before: #{before_chain.inspect} -> after: #{after_chain.inspect})"
    unless dropped.empty?
      lines << ""
      dropped.each do |d|
        lines << "  Dropped dead edge in #{d[:field]} -> #{d[:ref]}: target intent does not exist."
      end
    end
    "#{lines.join("\n")}\n"
  end

  # PURE. Render the dry-run/apply human-readable report.
  def render_report(base:, at:, prose_changes:, graph:, apply:)
    lines = []
    lines << "restore-intent-v1: #{base} at #{at} (#{apply ? "APPLY" : "DRY RUN"})"
    prose_changes.each { |f| lines << "  prose: revert #{f}" }
    lines << "  sources -> #{graph[:sources].inspect}"
    lines << "  chain -> #{graph[:chain].inspect}"
    graph[:dropped].each do |d|
      lines << "  DROPPED dead edge (#{d[:field]}): #{d[:ref]} - target intent does not exist"
    end
    graph[:unverified].each do |d|
      lines << "  UNVERIFIED edge (#{d[:field]}): #{d[:ref]} - store unknown, kept"
    end
    lines.join("\n")
  end
end
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd /Users/zlatko/apps/personal/plastic/.claude/worktrees/193--restore-to-v1-preserves-graph && ruby -Itest test/restore_intent_v1_lib_test.rb`
Expected: PASS, 4 runs, 0 failures, 0 errors.

- [ ] **Step 5: Commit**

```bash
cd /Users/zlatko/apps/personal/plastic/.claude/worktrees/193--restore-to-v1-preserves-graph
git add scripts/lib/restore_intent_v1.rb test/restore_intent_v1_lib_test.rb
git commit -m "feat: add RestoreIntentV1 pure graph math (union + target resolution)"
```

---

## Task 2: CLI shell `scripts/restore-intent-v1`

**Files:**
- Create: `scripts/restore-intent-v1`
- Modify: none (this task is the shell only; its subprocess tests live in Task 3-5)

- [ ] **Step 1: Write the implementation** (no isolated unit test for the shell itself; it is
  proven end-to-end by the subprocess tests in Tasks 3, 4, and 5, matching how
  `test/new_intent_test.rb` proves `scripts/new-intent`)

```ruby
#!/usr/bin/env ruby
# encoding: UTF-8
# frozen_string_literal: true

# restore-intent-v1 - restore a completed intent's PROSE to an explicit v1 git ref
# while preserving its frontmatter GRAPH (sources/chain) as a target-resolved
# union of the v1 snapshot and the current snapshot (intent 193). This is the
# ONLY sanctioned way to restore a completed intent to v1; a hand-run whole-file
# `git checkout`/revert is forbidden (see PLASTIC.md > Terminal immutability),
# because it cannot tell prose from graph metadata and silently destroys
# backlinks written after v1 (the 124/131 incident this tool exists to prevent).
#
# Usage:
#   restore-intent-v1 <intent-id> --at <git-ref> [--plastic-home PATH] [--apply] [--audit-path PATH]
#
# Dry-run by default (the OPPOSITE of rebuild-graph/project-links, which default
# to a real run): this tool is rarer and higher blast-radius, and this exact
# class of tool already destroyed live store data once. --apply is required to
# write.
#
# Restore-to-v1 runs under the MAINTENANCE lock (PLASTIC.md > Terminal
# immutability: the maintenance lock covers sanctioned structural move-and-record
# edits after completion). This tool does NOT acquire, check, or manage that
# lock itself (fail-open doctrine, intent 111: lock management is the
# orchestrator's job, never built into a CLI as a trap); it only prints a
# one-line reminder on --apply.
#
# Pure-Ruby (no bash). Graph math lives in lib/restore_intent_v1.rb and reuses
# lib/graph_rebuild.rb + lib/frontmatter_writer.rb verbatim; this shell does only
# discovery, git IO, and reporting. Never pushes ~/.plastic.

require "fileutils"
require "time"
require "open3"

require_relative "lib/store_discovery"
require_relative "lib/intent_validator"
require_relative "lib/graph_rebuild"
require_relative "lib/frontmatter_writer"
require_relative "lib/restore_intent_v1"

class RestoreIntentV1CLI
  DEFAULT_HOME = File.join(Dir.home, ".plastic")
  PROSE_SIBLINGS = %w[checklist.md outcome.md spec.md plan.md].freeze

  def self.parse_argv(argv)
    args = argv.dup
    intent_id = nil
    opts = { at: nil, plastic_home: DEFAULT_HOME, apply: false, audit_path: nil }
    i = 0
    while i < args.length
      case args[i]
      when "--at" then opts[:at] = args[i += 1]
      when "--plastic-home" then opts[:plastic_home] = args[i += 1]
      when "--apply" then opts[:apply] = true
      when "--audit-path" then opts[:audit_path] = args[i += 1]
      else
        intent_id ||= args[i]
      end
      i += 1
    end
    [intent_id, opts]
  end

  def initialize(intent_id, at:, plastic_home: DEFAULT_HOME, apply: false, audit_path: nil)
    @intent_id = intent_id
    @at = at
    @plastic_home = plastic_home
    @apply = apply
    @audit_path = audit_path
  end

  attr_reader :intent_id, :at, :plastic_home, :apply, :audit_path

  def run
    abort_loud("--at is required") if at.nil? || at.to_s.strip.empty?
    abort_loud("intent id is required") if intent_id.nil? || intent_id.to_s.strip.empty?
    abort_loud("--at #{at} does not resolve to a commit") unless ref_exists?

    discovery = StoreDiscovery.discover(plastic_home)
    dir, store_key = find_intent_dir(discovery, intent_id)
    abort_loud("intent #{intent_id} not found in any known store under #{plastic_home}") if dir.nil?

    base = File.basename(dir)
    md_path = File.join(dir, "#{base}.md")

    v1_md = git_show(relative(md_path))
    abort_loud("--at #{at} has no version of #{base}.md; aborting, no write") if v1_md.nil?

    current_md = File.read(md_path)
    current_fm = IntentValidator.parse_frontmatter_text(current_md)
    v1_fm = IntentValidator.parse_frontmatter_text(v1_md)
    abort_loud("v1 snapshot frontmatter unparseable; aborting, no write") if v1_fm.nil? || v1_fm.empty?
    abort_loud("current frontmatter unparseable; aborting, no write") if current_fm.nil? || current_fm.empty?

    store_index, relocation_map = build_resolution_inputs(discovery)

    graph = RestoreIntentV1.compute_graph(
      v1_sources: v1_fm["sources"], v1_chain: v1_fm["chain"],
      current_sources: current_fm["sources"], current_chain: current_fm["chain"],
      referer_store: store_key, relocation_map: relocation_map, store_index: store_index
    )

    new_md = RestoreIntentV1.apply_graph(v1_md, desired_sources: graph[:sources], desired_chain: graph[:chain])
    unless new_md.include?("sources:") && new_md.include?("chain:")
      abort_loud("frontmatter rewrite did not carry both arrays; aborting, no write")
    end

    other_files = {}
    PROSE_SIBLINGS.each do |f|
      path = File.join(dir, f)
      next unless File.exist?(path)

      v1_content = git_show(relative(path))
      other_files[f] = v1_content if v1_content && v1_content != File.read(path)
    end

    prose_changes = other_files.keys.dup
    prose_changes.unshift("#{base}.md") if new_md != current_md

    puts RestoreIntentV1.render_report(base: base, at: at, prose_changes: prose_changes, graph: graph, apply: apply)

    return unless apply

    File.write(md_path, new_md) if new_md != current_md
    other_files.each { |f, content| File.write(File.join(dir, f), content) }

    puts "Reminder: restore-to-v1 runs under the maintenance lock (PLASTIC.md > Terminal " \
         "immutability). Confirm the maintenance lock is held before this --apply."

    reproject_links
    append_revision(dir, base, graph, before_sources: current_fm["sources"], before_chain: current_fm["chain"])
  end

  private

  def ref_exists?
    _out, status = Open3.capture2("git", "-C", plastic_home, "rev-parse", "--verify", "--quiet", "#{at}^{commit}")
    status.success?
  end

  def git_show(rel_path)
    out, status = Open3.capture2("git", "-C", plastic_home, "show", "#{at}:#{rel_path}")
    status.success? ? out : nil
  end

  def relative(path)
    path.delete_prefix("#{plastic_home}/")
  end

  # id--slug directory resolution: exact id match on the dirname's segment before
  # the first "--" (matches the convention scripts/doctor.rb already uses), never
  # a start_with? scan, so "1" never matches "124--...".
  def find_intent_dir(discovery, id)
    discovery[:stores].each do |s|
      Dir.children(s[:store]).reject { |e| e.start_with?(".") }.each do |entry|
        full = File.join(s[:store], entry)
        next unless File.directory?(full)
        next unless entry.split("--", 2).first == id.to_s

        return [full, s[:key]]
      end
    end
    nil
  end

  # Build the store_index (store_key => bare ids present) and relocation_map
  # (from every store's INDEX.md ## Relocated log) that GraphRebuild.resolve_ref
  # needs, using the exact recipe scripts/rebuild-graph already uses.
  def build_resolution_inputs(discovery)
    store_index = {}
    index_texts = {}
    discovery[:stores].each do |s|
      store_index[s[:key]] = Dir.children(s[:store]).reject { |e| e.start_with?(".") }
                                 .select { |e| File.directory?(File.join(s[:store], e)) }
                                 .map { |e| e.split("--", 2).first }
      index_texts[s[:key]] = File.exist?(s[:index]) ? File.read(s[:index]) : ""
    end
    [store_index, GraphRebuild.build_relocation_map(index_texts)]
  end

  def reproject_links
    project_links = File.expand_path("project-links", __dir__)
    system(RbConfig.ruby, project_links, "--plastic-home", plastic_home)
    return if $?.success?

    warn "restore-intent-v1: ## Links may now be stale (project-links reprojection failed). " \
         "Rerun: ruby #{project_links} --plastic-home #{plastic_home}"
  end

  def append_revision(dir, base, graph, before_sources:, before_chain:)
    path = File.join(dir, "revisions.md")
    existing = File.exist?(path) ? File.read(path) : "# revisions.md\n\n"
    nums = existing.scan(/^## Revision v(\d+)/).flatten.map(&:to_i)
    n = (nums.max || 0) + 1

    entry = RestoreIntentV1.render_revision_entry(
      n, at: at, timestamp: Time.now.utc.strftime("%Y-%m-%d-%H:%M"),
      before_sources: before_sources, after_sources: graph[:sources],
      before_chain: before_chain, after_chain: graph[:chain],
      dropped: graph[:dropped]
    )
    File.write(path, "#{existing.chomp}\n\n#{entry}")
  end

  def abort_loud(message)
    warn "restore-intent-v1: #{message}"
    exit 1
  end
end

if $PROGRAM_NAME == __FILE__
  intent_id, opts = RestoreIntentV1CLI.parse_argv(ARGV)
  RestoreIntentV1CLI.new(intent_id, **opts).run
end
```

- [ ] **Step 2: Make it executable and smoke-test the argument errors**

```bash
chmod +x /Users/zlatko/apps/personal/plastic/.claude/worktrees/193--restore-to-v1-preserves-graph/scripts/restore-intent-v1
cd /Users/zlatko/apps/personal/plastic/.claude/worktrees/193--restore-to-v1-preserves-graph
ruby scripts/restore-intent-v1 999 ; echo "exit=$?"
```
Expected: `restore-intent-v1: --at is required` printed to stderr, `exit=1`.

- [ ] **Step 3: Commit**

```bash
cd /Users/zlatko/apps/personal/plastic/.claude/worktrees/193--restore-to-v1-preserves-graph
git add scripts/restore-intent-v1
git commit -m "feat: add restore-intent-v1 CLI shell"
```

---

## Task 3: The proof pair (the heart of the plan)

**Files:**
- Create: `test/restore_intent_v1_test.rb`

Build a hermetic tmpdir git store (the `test/new_intent_test.rb` `git init` pattern) and seed it
through the REAL `scripts/new-intent` subprocess, so I1 backlinks are written exactly as
production writes them. Shape: create intent A ("Delivered thing"), commit as v1 (tag this
commit's SHA); create intent B ("Later thing") with `--sources <A id>`, which correctly writes
A's `chain += B` (mirrors `8a8d505`); commit; make an in-place prose edit to A's `.md` (mirrors
`01a3911`); commit. Test 1 drives the OLD whole-file-revert (`git checkout <v1 sha> --
<path>`, the literal command `60a51bf` amounts to) and asserts the backlink is GONE. Test 2
drives the NEW tool over the identical fixture and asserts the backlink SURVIVES and the prose
is byte-identical to v1.

- [ ] **Step 1: Write the fixture helper and the failing tests**

```ruby
# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
require_relative "../scripts/lib/intent_validator"
require_relative "../scripts/lib/links_section"

class RestoreIntentV1Test < Minitest::Test
  NEW_INTENT = File.expand_path("../scripts/new-intent", __dir__)
  RESTORE = File.expand_path("../scripts/restore-intent-v1", __dir__)
  TEMPLATES = File.expand_path("../templates", __dir__)

  def setup
    @home = Dir.mktmpdir("restore-intent-v1")
    @store = File.join(@home, "store")
    FileUtils.mkdir_p(@store)
    File.write(File.join(@home, "INDEX.md"), "# Index\n\n## Relocated\n(none)\n")
    git("init", "-q")
    git("-c", "user.email=t@t", "-c", "user.name=t", "commit", "--allow-empty", "-q", "-m", "init")
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  def git(*args)
    out, status = Open3.capture2("git", "-C", @home, *args)
    raise "git #{args.join(" ")} failed: #{out}" unless status.success?

    out
  end

  def new_intent(*args)
    out, status = Open3.capture2(RbConfig.ruby, NEW_INTENT, "--templates", TEMPLATES, "--store", @store, *args)
    raise "new-intent failed: #{out}" unless status.success?

    out.strip
  end

  def commit_all(message)
    git("add", "-A")
    git("-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", message)
    git("rev-parse", "HEAD").strip
  end

  def frontmatter_of(dir)
    IntentValidator.parse_frontmatter(File.join(dir, "#{File.basename(dir)}.md"))
  end

  def chain_of(dir)
    Array(frontmatter_of(dir)["chain"]).map(&:to_s)
  end

  # Resolve an id back to its on-disk directory under @store (used by tests that
  # need the created intent's basename/label after the fact, e.g. a ## Links
  # assertion).
  def dir_for_id(id)
    Dir.children(@store).map { |e| File.join(@store, e) }
       .find { |d| File.basename(d).split("--", 2).first == id.to_s }
  end

  # Builds the 124/131-shaped fixture. Returns [a_dir, a_id, v1_sha].
  def seed_124_131_shape
    a_dir = new_intent("--intent", "Delivered thing", "--slug", "delivered-thing")
    a_id = File.basename(a_dir).split("--", 2).first
    v1_sha = commit_all("intent #{a_id} delivered")

    b_dir = new_intent("--intent", "Later thing", "--slug", "later-thing", "--sources", a_id)
    commit_all("feat: create later thing (sources #{a_id})")
    assert_includes chain_of(a_dir), File.basename(b_dir).split("--", 2).first,
      "fixture setup: new-intent must write the I1 backlink before the test proceeds"

    a_md = File.join(a_dir, "#{File.basename(a_dir)}.md")
    File.write(a_md, File.read(a_md) + "\n\n### Amendment\nA late ruling landed in place.\n")
    commit_all("intent #{a_id} amended in place")

    [a_dir, a_id, v1_sha]
  end

  # THE regression: the OLD hand-run behavior (60a51bf's literal mechanism) loses
  # the accrued I1 backlink because it is a whole-file revert with no concept of
  # graph metadata.
  def test_old_whole_file_revert_destroys_the_accrued_backlink
    a_dir, _a_id, v1_sha = seed_124_131_shape
    rel = relative_to_home(a_dir)

    git("checkout", v1_sha, "--", "#{rel}/#{File.basename(a_dir)}.md")

    refute_includes chain_of(a_dir), chain_of(a_dir).first.to_s.empty? ? "" : chain_of(a_dir).first,
      "sanity: chain should not be empty by coincidence" unless chain_of(a_dir).empty?
    assert_empty chain_of(a_dir),
      "the OLD whole-file revert must reproduce the real incident: chain reverts to v1's " \
      "empty array, destroying the accrued backlink"
  end

  # THE fix: the NEW tool preserves the backlink through an identical restore.
  def test_new_tool_preserves_the_accrued_backlink
    a_dir, a_id, v1_sha = seed_124_131_shape
    b_id_chain_before = chain_of(a_dir)

    out, status = Open3.capture2(
      RbConfig.ruby, RESTORE, a_id, "--at", v1_sha, "--plastic-home", @home, "--apply"
    )
    assert_equal 0, status.exitstatus, "restore should succeed: #{out}"

    assert_equal b_id_chain_before, chain_of(a_dir),
      "the accrued backlink must survive the restore"
    refute_includes File.read(File.join(a_dir, "#{File.basename(a_dir)}.md")), "A late ruling landed in place",
      "the amendment prose must be reverted to v1"
  end

  # Path relative to @home (the fixture's git repo root), for `git checkout <sha>
  # -- <path>` invocations run directly against the fixture (not through the CLI).
  def relative_to_home(dir)
    dir.delete_prefix("#{@home}/")
  end
end
```

- [ ] **Step 2: Run to verify both fail for the right reason**

Run: `cd /Users/zlatko/apps/personal/plastic/.claude/worktrees/193--restore-to-v1-preserves-graph && ruby -Itest test/restore_intent_v1_test.rb`
Expected: `test_old_whole_file_revert_destroys_the_accrued_backlink` PASSES already (it exercises
only git, no new code) proving the regression is real; `test_new_tool_preserves_the_accrued_backlink`
FAILS (restore-intent-v1 exits nonzero or the CLI has a bug) until Task 2's shell is correct end
to end. If the old-behavior test does NOT fail-to-lose-the-backlink (i.e. it unexpectedly keeps
the backlink), STOP: the fixture does not reproduce the incident and must be fixed before
proceeding, per the no-tautological-tests rule.

- [ ] **Step 3: Fix any CLI issues found running the new-tool test until it passes**

Run the same command until both tests pass. Common gaps to check: `find_intent_dir` matching,
`ref_exists?` needing a full commit (not a working-tree-only state), `store_index` needing the
store's OWN id excluded or included consistently (it is fine to include the referer's own id,
`resolve_ref` never resolves an id against itself in this shape since chain entries never
self-reference).

- [ ] **Step 4: Commit**

```bash
cd /Users/zlatko/apps/personal/plastic/.claude/worktrees/193--restore-to-v1-preserves-graph
git add test/restore_intent_v1_test.rb
git commit -m "test: prove restore-intent-v1 preserves the 124/131-shaped backlink"
```

---

## Task 4: Target resolution, dry-run default, whole-directory revert, and Links preservation

**Files:**
- Modify: `test/restore_intent_v1_test.rb`

Two concerns land in this task. First, SYNTHETIC fixtures exercising the general
target-resolution safeguard (D14): do not name them or comment them as "the real 124 case",
verified directly against git history that 124's actual v1 held `chain: []`, with no dangling
edge ever present in it. Second, three more `spec.md` acceptance criteria not yet covered by
Tasks 3-4's first two tests: dry-run (no `--apply`) must make ZERO filesystem writes, the four
prose siblings (`checklist.md`/`outcome.md`/`spec.md`/`plan.md`) must revert to their exact v1
bytes (the real `60a51bf` touched exactly these four file kinds besides the intent's own `.md`),
and `## Links` must reflect the preserved graph after an applied restore, asserted directly
against the expected rendered text (never by shelling out to `scripts/project-links` to verify,
since intent 192 is rewriting its CLI surface concurrently in this same session; the TOOL itself
still calls `project-links` for real at `--apply` time, per Task 2).

- [ ] **Step 1: Add the failing tests**

```ruby
  # Synthetic: v1's chain names an id with no directory anywhere in the fixture
  # store. This is a general hardening (D14), not a replay of the 124 incident,
  # whose real v1 snapshot held chain: [] with no dangling edge.
  def test_dead_v1_edge_is_dropped_and_reported
    a_dir = new_intent("--intent", "Has a dead edge", "--slug", "has-dead-edge")
    a_id = File.basename(a_dir).split("--", 2).first
    a_md = File.join(a_dir, "#{File.basename(a_dir)}.md")

    # Hand-craft v1's frontmatter to carry a dead edge (an id nothing scaffolds),
    # exactly the shape a real historical v1 could carry if its target were later
    # deleted; this is what the fixture is testing, not something new-intent
    # would ever produce on its own.
    content = File.read(a_md)
    content = content.sub('chain: []', 'chain: ["999"]')
    File.write(a_md, content)
    v1_sha = commit_all("intent #{a_id} delivered with a since-dead edge")

    # Revert the dead edge back out of the working file (simulating that nothing
    # legitimately re-added it later); current chain is empty.
    File.write(a_md, File.read(a_md).sub('chain: ["999"]', "chain: []"))
    commit_all("intent #{a_id} amended in place")

    out, status = Open3.capture2(
      RbConfig.ruby, RESTORE, a_id, "--at", v1_sha, "--plastic-home", @home, "--apply"
    )
    assert_equal 0, status.exitstatus, "restore should succeed: #{out}"
    assert_empty chain_of(a_dir), "a confirmed-dead v1 edge must not be reintroduced"
    assert_includes out, "999", "the dropped dead edge must be named in the report"

    revisions = File.read(File.join(a_dir, "revisions.md"))
    assert_includes revisions, "999", "the dropped dead edge must be recorded in revisions.md"
  end

  # Synthetic, combining a dead v1 edge with a live, legitimately-accrued current
  # edge: the single most valuable target-resolution test, since it proves the
  # restore recovers exactly the TRUE current graph, never the dead edge and
  # never a naive union of both.
  def test_dead_v1_edge_dropped_while_live_current_edge_survives
    a_dir = new_intent("--intent", "Has both edges", "--slug", "has-both-edges")
    a_id = File.basename(a_dir).split("--", 2).first
    a_md = File.join(a_dir, "#{File.basename(a_dir)}.md")

    content = File.read(a_md).sub('chain: []', 'chain: ["999"]')
    File.write(a_md, content)
    v1_sha = commit_all("intent #{a_id} delivered with a since-dead edge")

    File.write(a_md, File.read(a_md).sub('chain: ["999"]', "chain: []"))
    commit_all("intent #{a_id} amended in place")

    b_dir = new_intent("--intent", "Live accrual", "--slug", "live-accrual", "--sources", a_id)
    commit_all("feat: create live accrual (sources #{a_id})")
    b_id = File.basename(b_dir).split("--", 2).first
    assert_equal [b_id], chain_of(a_dir), "fixture setup: only the live backlink should be present"

    out, status = Open3.capture2(
      RbConfig.ruby, RESTORE, a_id, "--at", v1_sha, "--plastic-home", @home, "--apply"
    )
    assert_equal 0, status.exitstatus, "restore should succeed: #{out}"
    assert_equal [b_id], chain_of(a_dir),
      "restored chain must be exactly the live accrued edge, no dead edge, no duplication"
  end

  # Dry-run (no --apply) is the default: it must exit 0, print a report, and
  # touch NO file on disk, not even the .md file's frontmatter.
  def test_dry_run_is_default_no_filesystem_write
    a_dir, a_id, v1_sha = seed_124_131_shape
    a_md = File.join(a_dir, "#{File.basename(a_dir)}.md")
    before_md = File.read(a_md)
    before_chain = chain_of(a_dir)

    out, status = Open3.capture2(
      RbConfig.ruby, RESTORE, a_id, "--at", v1_sha, "--plastic-home", @home
    )
    assert_equal 0, status.exitstatus, "a dry run should still exit 0: #{out}"
    assert_equal before_md, File.read(a_md), "dry run (no --apply) must not write the .md file"
    assert_equal before_chain, chain_of(a_dir), "dry run must not change the frontmatter graph"
    assert_includes out, "DRY RUN", "dry-run output must say so explicitly"
  end

  # The real 60a51bf restore touched exactly these four lifecycle files besides
  # the intent's own .md (138 deletions / 2 insertions across all four in that
  # single commit). Prove every one of them reverts to its exact v1 byte content.
  def test_apply_reverts_all_four_lifecycle_siblings_to_exact_v1_bytes
    a_dir = new_intent("--intent", "Full lifecycle files", "--slug", "full-lifecycle")
    a_id = File.basename(a_dir).split("--", 2).first
    siblings = %w[checklist.md outcome.md spec.md plan.md]
    v1_bytes = siblings.to_h { |f| [f, File.read(File.join(a_dir, f))] }
    v1_sha = commit_all("intent #{a_id} delivered")

    siblings.each { |f| File.write(File.join(a_dir, f), "#{v1_bytes[f]}\nlate edit\n") }
    commit_all("intent #{a_id} lifecycle files amended in place")

    out, status = Open3.capture2(
      RbConfig.ruby, RESTORE, a_id, "--at", v1_sha, "--plastic-home", @home, "--apply"
    )
    assert_equal 0, status.exitstatus, "restore should succeed: #{out}"
    siblings.each do |f|
      assert_equal v1_bytes[f], File.read(File.join(a_dir, f)),
        "#{f} must revert to its exact v1 byte content"
    end
  end

  # ## Links must reflect the PRESERVED graph after an applied restore. Asserted
  # directly against the canonical projected text (matching the exact format
  # test/new_intent_test.rb already pins for a chain-only backlink: sources
  # first, chain second, "- [[basename|label]]" per entry), never by shelling
  # out to scripts/project-links, whose CLI surface intent 192 is rewriting
  # concurrently in this same session. The TOOL itself still calls project-links
  # for real at --apply time (Task 2's reproject_links); this test observes the
  # resulting file, it does not re-invoke project-links itself.
  def test_links_section_reflects_the_preserved_graph_after_apply
    a_dir, a_id, v1_sha = seed_124_131_shape
    b_id = chain_of(a_dir).first
    b_dir = dir_for_id(b_id)
    refute_nil b_dir, "fixture setup: B's directory must resolve"

    out, status = Open3.capture2(
      RbConfig.ruby, RESTORE, a_id, "--at", v1_sha, "--plastic-home", @home, "--apply"
    )
    assert_equal 0, status.exitstatus, "restore should succeed: #{out}"

    a_md = File.join(a_dir, "#{File.basename(a_dir)}.md")
    body = IntentValidator.body_of(File.read(a_md))
    expected = "## Links\n- [[#{File.basename(b_dir)}|Later thing]]\n"
    assert_equal expected, LinksSection.extract_section(body),
      "## Links must reflect the preserved chain edge after an applied restore"
  end
```

- [ ] **Step 2: Run to verify they fail, then fix, then pass**

Run: `cd /Users/zlatko/apps/personal/plastic/.claude/worktrees/193--restore-to-v1-preserves-graph && ruby -Itest test/restore_intent_v1_test.rb`
Expected initially: failures pointing at any gap in Task 1's `resolve_union`/`compute_graph`,
Task 2's report text, or Task 2's `reproject_links` call. Iterate until all five tests added in
this task pass. If the Links test fails, first confirm `scripts/project-links` is actually being
invoked and exits 0 by running it by hand against the fixture's own `@home` before touching the
test's assertion.

- [ ] **Step 3: Commit**

```bash
cd /Users/zlatko/apps/personal/plastic/.claude/worktrees/193--restore-to-v1-preserves-graph
git add test/restore_intent_v1_test.rb
git commit -m "test: prove target resolution, dry-run default, whole-directory revert, Links preservation"
```

---

## Task 5: Fail-loud tests

**Files:**
- Modify: `test/restore_intent_v1_test.rb`

Each asserts BOTH a non-zero exit AND that the on-disk file is byte-for-byte unchanged (never
just the exit code).

- [ ] **Step 1: Add the failing tests**

```ruby
  def test_unresolved_at_aborts_with_no_write
    a_dir = new_intent("--intent", "Untouched", "--slug", "untouched")
    a_id = File.basename(a_dir).split("--", 2).first
    a_md = File.join(a_dir, "#{File.basename(a_dir)}.md")
    commit_all("intent #{a_id} delivered")
    before = File.read(a_md)

    out, status = Open3.capture2(
      RbConfig.ruby, RESTORE, a_id, "--at", "not-a-real-ref", "--plastic-home", @home, "--apply"
    )
    refute_equal 0, status.exitstatus, "must exit non-zero: #{out}"
    assert_equal before, File.read(a_md), "file must be byte-for-byte unchanged"
  end

  def test_unresolved_intent_id_aborts_with_no_write
    a_dir = new_intent("--intent", "Untouched two", "--slug", "untouched-two")
    a_md = File.join(a_dir, "#{File.basename(a_dir)}.md")
    v1_sha = commit_all("intent delivered")
    before = File.read(a_md)

    out, status = Open3.capture2(
      RbConfig.ruby, RESTORE, "999999", "--at", v1_sha, "--plastic-home", @home, "--apply"
    )
    refute_equal 0, status.exitstatus, "must exit non-zero: #{out}"
    assert_equal before, File.read(a_md), "file must be byte-for-byte unchanged"
  end

  def test_unparseable_v1_frontmatter_aborts_with_no_write
    a_dir = new_intent("--intent", "Bad v1", "--slug", "bad-v1")
    a_id = File.basename(a_dir).split("--", 2).first
    a_md = File.join(a_dir, "#{File.basename(a_dir)}.md")

    # Corrupt v1's frontmatter itself (no closing --- delimiter), commit it as v1.
    File.write(a_md, "---\nid: \"#{a_id}\"\nsources: [\nno closing delimiter here")
    v1_sha = commit_all("intent #{a_id} delivered with broken frontmatter")

    # Restore the working copy to something valid so "current" is readable, but
    # v1 (the committed snapshot) remains broken.
    good_a_dir = new_intent("--intent", "Bad v1 fixed", "--slug", "bad-v1-fixed")
    FileUtils.cp(File.join(good_a_dir, "#{File.basename(good_a_dir)}.md"), a_md)
    commit_all("intent #{a_id} amended in place")
    before = File.read(a_md)

    out, status = Open3.capture2(
      RbConfig.ruby, RESTORE, a_id, "--at", v1_sha, "--plastic-home", @home, "--apply"
    )
    refute_equal 0, status.exitstatus, "must exit non-zero: #{out}"
    assert_equal before, File.read(a_md), "file must be byte-for-byte unchanged"
  end
```

- [ ] **Step 2: Run, fix any gap, verify all pass**

Run: `cd /Users/zlatko/apps/personal/plastic/.claude/worktrees/193--restore-to-v1-preserves-graph && ruby -Itest test/restore_intent_v1_test.rb`
Expected: PASS, all tests in the file green.

- [ ] **Step 3: Commit**

```bash
cd /Users/zlatko/apps/personal/plastic/.claude/worktrees/193--restore-to-v1-preserves-graph
git add test/restore_intent_v1_test.rb
git commit -m "test: prove restore-intent-v1 fails loud with no partial write"
```

---

## Task 6: Documentation edits

**Files:**
- Modify: `PLASTIC.md:624` (the "Terminal immutability" paragraph)
- Modify: `skills/intent-creating/SKILL.md:55-68` (the "Decide Branch vs Root" section)

- [ ] **Step 1: Edit `PLASTIC.md`**

Anchor (exact current text starting at line 624):

```
Terminal immutability (the contract intent 112 enforces): a terminal directory is writable
ONLY while a lock is held. The delivery lock covers the completing session's End tail up to
`Lock.release`; the maintenance lock covers sanctioned structural move-and-record edits
after. Terminal with no lock held is frozen. There are only two locks in the system,
delivery and maintenance (108 D11). This governs WRITES only: reads of a terminal intent are
always allowed and unbounded (curator reindex, dashboards, and future intents that reference
its id or chain), so a done intent stays fully readable forever. Intent 93 states this rule;
intent 112 builds the gate that enforces it.
```

Insert immediately after that paragraph (new paragraph, same section):

```
Restore-to-v1 (the owner rule that a completed intent is immutable: a late ruling goes to a
new `--parent` branch intent, and the completed intent is restored to v1) is performed ONLY by
`scripts/restore-intent-v1`, run under the maintenance lock. Its prose (the intent narrative,
checklist.md, outcome.md, spec.md, plan.md) is immutable and reverts to v1; its frontmatter
graph (`sources`/`chain`) is metadata about OTHER intents, not content of this one, and is
APPEND-ONLY: it is preserved as the union of the v1 snapshot and the current snapshot, never
subtracted. A hand-run whole-file `git checkout`/revert of a completed intent is FORBIDDEN,
because it cannot distinguish prose from graph metadata and silently destroys backlinks written
after v1 (proven on intent 124: a legitimately accrued chain edge was destroyed by a hand-run
restore and went undetected for a week). This governs the restore mechanism only; it does not
loosen terminal immutability itself.
```

- [ ] **Step 2: Edit `skills/intent-creating/SKILL.md`**

Anchor (exact current text, the last bullet of "### 2. Decide Branch vs Root", lines 58-59):

```
- **Branch (`14a`, `14b`)**: a sub-task, refinement, or direct continuation. It only
  makes sense as part of the parent's work. Pass `--parent <parent_id>`.
```

Insert immediately after the full bulleted list (after the "Rule of thumb" bullet, before the
`## Links` paragraph that currently follows at line 72), a new paragraph:

```
When a branch intent exists because a late ruling arrived AFTER its parent was already
completed (the owner's late-ruling rule), the parent is restored to v1 via
`scripts/restore-intent-v1`, never by a hand-run `git checkout`/revert. See `PLASTIC.md` >
Terminal immutability for the rule and the tool.
```

- [ ] **Step 3: Verify no em-dashes were introduced**

Run: `cd /Users/zlatko/apps/personal/plastic/.claude/worktrees/193--restore-to-v1-preserves-graph && grep -n $'—\|–' PLASTIC.md skills/intent-creating/SKILL.md`
Expected: no output (exit 1).

- [ ] **Step 4: Commit**

```bash
cd /Users/zlatko/apps/personal/plastic/.claude/worktrees/193--restore-to-v1-preserves-graph
git add PLASTIC.md skills/intent-creating/SKILL.md
git commit -m "docs: codify restore-intent-v1 as the sanctioned restore-to-v1 procedure"
```

---

## Task 7: Full suite green, em-dash guard, final commit

- [ ] **Step 1: Run the full suite**

Run: `cd /Users/zlatko/apps/personal/plastic/.claude/worktrees/193--restore-to-v1-preserves-graph && bin/test`
Expected: PASS, 0 failures, 0 errors, including every pre-existing test file (this new work must
not regress anything else, especially `test/graph_rebuild_test.rb`, `test/frontmatter_writer_test.rb`
if it exists, and `test/new_intent_test.rb`, all of which share code with this new tool).

- [ ] **Step 2: Em-dash / en-dash guard on the whole diff**

Run: `cd /Users/zlatko/apps/personal/plastic/.claude/worktrees/193--restore-to-v1-preserves-graph && git diff main --unified=0 | grep '^+' | grep -n $'—\|–'`
Expected: no output. If any hit, fix it (hyphen, comma, or colon) and re-run Step 1.

- [ ] **Step 3: Confirm the acceptance criteria from spec.md, one by one**

Walk every checkbox in `spec.md`'s `## Acceptance Criteria` and confirm each is demonstrably true
(a passing test, a `grep` hit, or a manual command run and its output pasted into the checklist
Session Log). Do not check a box on inspection alone when a command can prove it.

- [ ] **Step 4: Final status check**

```bash
cd /Users/zlatko/apps/personal/plastic/.claude/worktrees/193--restore-to-v1-preserves-graph
git status
git log --oneline main..HEAD
```
Expected: clean working tree, a linear stack of the commits made in Tasks 1-6 on top of `main`.
