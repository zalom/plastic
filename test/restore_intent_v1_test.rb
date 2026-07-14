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
end
