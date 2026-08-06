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
    new_intent_in(@store, *args)
  end

  # Same as new_intent, but against an explicit store path (used by the
  # ambiguous-bare-id test, which needs two independent stores under one home).
  def new_intent_in(store, *args)
    out, status = Open3.capture2(RbConfig.ruby, NEW_INTENT, "--templates", TEMPLATES, "--store", store, *args)
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

  def sources_of(dir)
    Array(frontmatter_of(dir)["sources"]).map(&:to_s)
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
    # legitimately re-added it later); current chain is empty. Also land an unrelated
    # prose amendment: current's chain already equals the post-drop union on its own,
    # so without an independent real change this restore would be a genuine no-op
    # (correctly writing no revisions.md at all, per intent 197's append-only-on-
    # real-change discipline) and this test's final assertion would have nothing to
    # observe.
    current = File.read(a_md).sub('chain: ["999"]', "chain: []")
    current += "\n\n### Amendment\nSomething unrelated changed after v1.\n"
    File.write(a_md, current)
    commit_all("intent #{a_id} amended in place")

    # The drop must be named in BOTH the dry-run report and the apply report
    # (spec acceptance criterion names both explicitly), not only on --apply.
    dry_out, dry_status = Open3.capture2(
      RbConfig.ruby, RESTORE, a_id, "--at", v1_sha, "--plastic-home", @home
    )
    assert_equal 0, dry_status.exitstatus, "dry run should succeed: #{dry_out}"
    assert_includes dry_out, "999", "the dropped dead edge must be named in the DRY RUN report"
    assert_empty chain_of(a_dir), "a dry run must not have written anything yet"

    out, status = Open3.capture2(
      RbConfig.ruby, RESTORE, a_id, "--at", v1_sha, "--plastic-home", @home, "--apply"
    )
    assert_equal 0, status.exitstatus, "restore should succeed: #{out}"
    assert_empty chain_of(a_dir), "a confirmed-dead v1 edge must not be reintroduced"
    assert_includes out, "999", "the dropped dead edge must be named in the APPLY report"

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

  # AC (spec.md): --apply reverts the intent's own .md while sources/chain equals
  # the union, "verified by reading the written file back and diffing prose
  # against the v1 git blob byte-for-byte outside the two frontmatter array
  # lines." This test performs exactly that diff, directly against the real git
  # blob at v1_sha, not merely against a substring check.
  def test_apply_restores_md_byte_identical_to_v1_outside_graph_arrays
    a_dir, a_id, v1_sha = seed_124_131_shape
    a_md = File.join(a_dir, "#{File.basename(a_dir)}.md")
    rel = relative_to_home(a_dir)
    v1_blob = git("show", "#{v1_sha}:#{rel}/#{File.basename(a_dir)}.md")

    out, status = Open3.capture2(
      RbConfig.ruby, RESTORE, a_id, "--at", v1_sha, "--plastic-home", @home, "--apply"
    )
    assert_equal 0, status.exitstatus, "restore should succeed: #{out}"

    # Strip the two graph frontmatter lines AND the ## Links section: Links is a
    # DERIVED projection of the graph (re-projected after an applied restore, per
    # Goal 4), not immutable prose, so it legitimately differs from v1 whenever
    # the graph itself legitimately differs (exactly this fixture's case).
    normalize = lambda do |text|
      without_graph_lines = text.lines.reject { |l| l.match?(/\A(sources|chain):/) }.join
      without_graph_lines.sub(/^## Links\n.*\z/m, "")
    end
    assert_equal normalize.call(v1_blob), normalize.call(File.read(a_md)),
      "the restored .md must be byte-identical to v1 outside the sources/chain frontmatter " \
      "lines and the derived ## Links section"
  end

  # AC (spec.md): the revisions.md entry names the reverted files. Intent 197 wired
  # RevisionsWriter into project-links too, so a restore that ALSO changes the target's
  # own ## Links section (because its graph changed) now gains a SECOND, separate entry:
  # one from project-links (the mechanical ## Links regeneration, reprojected as a normal
  # part of handle_links_reprojection) and one from restore-intent-v1 itself (the semantic
  # graph/prose restore). Both are real, distinct structural changes, so both get their own
  # receipt; this is the intended, more complete audit trail, not a duplicate.
  def test_revisions_gains_restored_to_v1_entry_naming_reverted_files
    a_dir, a_id, v1_sha = seed_124_131_shape

    out, status = Open3.capture2(
      RbConfig.ruby, RESTORE, a_id, "--at", v1_sha, "--plastic-home", @home, "--apply"
    )
    assert_equal 0, status.exitstatus, "restore should succeed: #{out}"

    revisions = File.read(File.join(a_dir, "revisions.md"))
    assert_equal 2, revisions.scan(/^## Revision v\d+/).length,
      "one entry from project-links' own ## Links reprojection plus one from restore-intent-v1 itself"
    assert_includes revisions, "restored-to-v1", "the entry must carry the restored-to-v1 tag"
    assert_includes revisions, "links-projection",
      "the target's own ## Links regeneration (triggered by the restored graph) must carry its own receipt"
    assert_includes revisions, "#{File.basename(a_dir)}.md",
      "the entry must name the reverted intent .md file"
  end

  # AC (spec.md): --apply prints a one-line reminder naming the maintenance
  # lock; the tool never calls lock-acquisition/lock-check code (verified
  # structurally: scripts/restore-intent-v1 never requires lib/lock.rb).
  def test_apply_prints_maintenance_lock_reminder
    a_dir, a_id, v1_sha = seed_124_131_shape

    out, status = Open3.capture2(
      RbConfig.ruby, RESTORE, a_id, "--at", v1_sha, "--plastic-home", @home, "--apply"
    )
    assert_equal 0, status.exitstatus, "restore should succeed: #{out}"
    assert_includes out, "There is no maintenance lock to hold",
      "an --apply run must print the corrected no-lock reminder (fail-open doctrine, 111), " \
      "not the earlier wrong doctrine that a maintenance lock must be held"

    refute_includes File.read(RESTORE), "lib/lock\"",
      "the tool itself must never require the lock library (fail-open doctrine, 111)"
  end

  # BLOCKING 1 regression test: a prose sibling that existed at v1 but was
  # DELETED after v1 must be restored (recreated with its exact v1 bytes) and
  # named in the report. Gating the restore loop on "does the file exist NOW"
  # (instead of "did it exist AT V1") silently never restores it: the exact
  # class of silent loss this intent exists to kill, just on a prose file
  # instead of a graph edge.
  def test_prose_sibling_deleted_after_v1_is_restored_not_silently_skipped
    a_dir = new_intent("--intent", "Sibling gets deleted", "--slug", "sibling-deleted")
    a_id = File.basename(a_dir).split("--", 2).first
    checklist_path = File.join(a_dir, "checklist.md")
    v1_checklist_bytes = File.read(checklist_path)
    v1_sha = commit_all("intent #{a_id} delivered")

    File.delete(checklist_path)
    commit_all("intent #{a_id} checklist.md deleted after v1")
    refute File.exist?(checklist_path), "fixture setup: checklist.md must be gone before the restore"

    out, status = Open3.capture2(
      RbConfig.ruby, RESTORE, a_id, "--at", v1_sha, "--plastic-home", @home, "--apply"
    )
    assert_equal 0, status.exitstatus, "restore should succeed: #{out}"
    assert File.exist?(checklist_path), "a sibling deleted after v1 must be RECREATED by the restore"
    assert_equal v1_checklist_bytes, File.read(checklist_path),
      "the recreated sibling must have v1's exact byte content"
    assert_includes out, "checklist.md", "the recreated sibling must be named in the report"
  end

  # Fix 3: the "unconfirmed graph write" fail-loud path. v1's frontmatter is
  # valid YAML but carries no sources:/chain: keys at all, so
  # FrontmatterWriter.rewrite_arrays has nothing to rewrite (a no-op on those
  # two keys). The computed union (a real, existing chain target) would then be
  # silently absent from the written file unless the write is re-parsed and
  # confirmed against what was computed. This forces that path.
  def test_v1_frontmatter_missing_graph_keys_aborts_via_write_confirmation
    other_dir = new_intent("--intent", "Real other intent", "--slug", "real-other-intent")
    other_id = File.basename(other_dir).split("--", 2).first
    commit_all("intent #{other_id} delivered")

    a_dir = new_intent("--intent", "Missing graph keys", "--slug", "missing-graph-keys")
    a_id = File.basename(a_dir).split("--", 2).first
    a_md = File.join(a_dir, "#{File.basename(a_dir)}.md")

    minimal = <<~MD
      ---
      id: "#{a_id}"
      intent: "Missing graph keys"
      created: 2026-01-01
      author: human
      tags: []
      ---

      ## Intent
      Missing graph keys.
    MD
    File.write(a_md, minimal)
    v1_sha = commit_all("intent #{a_id} delivered with no sources:/chain: keys in frontmatter")

    File.write(a_md, minimal.sub("tags: []", "tags: []\nchain: [\"#{other_id}\"]"))
    commit_all("intent #{a_id} amended with a chain edge; v1 still has no chain: key")
    before = File.read(a_md)

    out, status = Open3.capture2(
      RbConfig.ruby, RESTORE, a_id, "--at", v1_sha, "--plastic-home", @home, "--apply"
    )
    refute_equal 0, status.exitstatus, "must exit non-zero: #{out}"
    assert_equal before, File.read(a_md), "file must be byte-for-byte unchanged"
  end

  # Fix 4: sources is never exercised end to end through the CLI elsewhere in
  # this file (only chain is). The AC says "sources/chain frontmatter equals
  # the union"; this proves the sources half.
  def test_sources_edge_is_preserved_through_a_restore
    root_dir = new_intent("--intent", "Root for sources", "--slug", "root-for-sources")
    root_id = File.basename(root_dir).split("--", 2).first
    commit_all("root delivered")

    restorable_dir = new_intent("--intent", "Restorable with sources", "--slug", "restorable-sources",
                                 "--sources", root_id)
    restorable_id = File.basename(restorable_dir).split("--", 2).first
    v1_sha = commit_all("intent #{restorable_id} delivered with sources #{root_id}")
    assert_includes sources_of(restorable_dir), root_id, "fixture setup: sources must be wired"

    restorable_md = File.join(restorable_dir, "#{File.basename(restorable_dir)}.md")
    File.write(restorable_md, File.read(restorable_md) + "\n\n### Amendment\nLate ruling.\n")
    commit_all("intent #{restorable_id} amended in place")

    out, status = Open3.capture2(
      RbConfig.ruby, RESTORE, restorable_id, "--at", v1_sha, "--plastic-home", @home, "--apply"
    )
    assert_equal 0, status.exitstatus, "restore should succeed: #{out}"
    assert_includes sources_of(restorable_dir), root_id, "the sources edge must survive the restore"
  end

  # Fix 5: a bare id present in more than one store is ambiguous. Given this
  # tool's blast radius, it must abort loud and name every candidate rather
  # than silently guessing the first store discovered.
  def test_ambiguous_bare_id_across_stores_aborts_loud_naming_both_candidates
    home = Dir.mktmpdir("restore-intent-v1-ambiguous")
    global = File.join(home, "store")
    proj = File.join(home, "projects", "sibling-project", "store")
    [global, proj].each { |d| FileUtils.mkdir_p(d) }
    File.write(File.join(home, "INDEX.md"), "# Index\n\n## Relocated\n(none)\n")
    File.write(File.join(home, "projects", "sibling-project", "INDEX.md"), "# Index\n\n## Relocated\n(none)\n")

    g_dir = new_intent_in(global, "--intent", "Global one", "--slug", "global-one")
    p_dir = new_intent_in(proj, "--intent", "Project one", "--slug", "project-one")
    g_id = File.basename(g_dir).split("--", 2).first
    p_id = File.basename(p_dir).split("--", 2).first
    assert_equal g_id, p_id, "fixture setup: both stores must allocate the same first bare id"

    Open3.capture2("git", "-C", home, "init", "-q")
    Open3.capture2("git", "-C", home, "add", "-A")
    Open3.capture2("git", "-C", home, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "init")
    head, = Open3.capture2("git", "-C", home, "rev-parse", "HEAD")
    head = head.strip

    out, status = Open3.capture2e(
      RbConfig.ruby, RESTORE, g_id, "--at", head, "--plastic-home", home, "--apply"
    )
    refute_equal 0, status.exitstatus, "an ambiguous bare id must abort loud rather than guess: #{out}"
    assert_includes out.downcase, "ambiguous"
    assert_includes out, "global", "both candidate stores must be named"
    assert_includes out, "sibling-project", "both candidate stores must be named"
  ensure
    FileUtils.rm_rf(home) if home
  end

  # Fix 7: the store-wide Links reprojection blast radius must be announced
  # unmissably, and --skip-links must let an operator decline it (with a loud
  # staleness warning instead of a silent skip).
  def test_apply_announces_store_wide_links_reprojection
    a_dir, a_id, v1_sha = seed_124_131_shape

    out, status = Open3.capture2(
      RbConfig.ruby, RESTORE, a_id, "--at", v1_sha, "--plastic-home", @home, "--apply"
    )
    assert_equal 0, status.exitstatus, "restore should succeed: #{out}"
    assert_includes out.downcase, "store-wide", "the store-wide blast radius must be announced"
  end

  def test_skip_links_declines_reprojection_with_a_loud_staleness_warning
    a_dir, a_id, v1_sha = seed_124_131_shape

    out, status = Open3.capture2e(
      RbConfig.ruby, RESTORE, a_id, "--at", v1_sha, "--plastic-home", @home, "--apply", "--skip-links"
    )
    assert_equal 0, status.exitstatus, "restore should succeed: #{out}"
    assert_includes out.downcase, "stale", "declining reprojection must print a loud staleness warning"
  end

  # --- ACTION_6 (intent 197): prove the existing writer already satisfies append-only vN+1 ---

  # FALSIFIABLE (208): append-only. Seed the target intent with a PRE-EXISTING
  # revisions.md (v1, unrelated to this restore) before running --apply, and confirm the
  # restore's own entry lands as v2 (or later), with v1's exact text still present verbatim.
  def test_preexisting_revisions_md_is_preserved_and_new_entry_appends_after_it
    a_dir, a_id, v1_sha = seed_124_131_shape

    preexisting = "# revisions.md\n\n## Revision v1 - 2026-01-01-00:00\n" \
                  "- Why: unrelated prior structural fix [rule: unsanctioned-section]\n" \
                  "- Prior location: #{File.basename(a_dir)}.md - ## Scratch\n" \
                  "- Content held:\n\n  ## Scratch\n  old junk\n"
    revisions_path = File.join(a_dir, "revisions.md")
    File.write(revisions_path, preexisting)

    out, status = Open3.capture2(
      RbConfig.ruby, RESTORE, a_id, "--at", v1_sha, "--plastic-home", @home, "--apply"
    )
    assert_equal 0, status.exitstatus, "restore should succeed: #{out}"

    revisions = File.read(revisions_path)
    assert_includes revisions, "## Revision v1 - 2026-01-01-00:00", "the pre-existing v1 entry must survive verbatim"
    assert_includes revisions, "unrelated prior structural fix", "v1's exact text must not be altered"
    assert_includes revisions, "restored-to-v1", "the restore's own entry must be present"
    refute_includes revisions, "## Revision v1 -\n- Why: restore-to-v1",
      "the restore's own entry must never overwrite the pre-existing v1 entry"
    # Numbering must be strictly increasing (append-only): every entry after v1 has a
    # higher number, never a repeat of v1.
    numbers = revisions.scan(/^## Revision v(\d+)/).flatten.map(&:to_i)
    assert_equal numbers.sort, numbers.uniq.sort, "no revision number may repeat"
    assert numbers.all? { |n| n >= 1 }, "every entry must be v1 or later"
    assert numbers.length >= 2, "the pre-existing entry plus at least one new entry must both be present"
  end

  # FALSIFIABLE (208) counterpart: a SECOND restore run (idempotent no-op, since the
  # intent is already at v1) must NOT append a spurious content-free entry when nothing
  # actually changed. (Establishes the "no-op yields no entry" floor so the test above is
  # not vacuously passing on a tool that appends unconditionally on every invocation.)
  def test_idempotent_second_restore_appends_no_further_entry_when_already_at_v1
    a_dir, a_id, v1_sha = seed_124_131_shape

    Open3.capture2(RbConfig.ruby, RESTORE, a_id, "--at", v1_sha, "--plastic-home", @home, "--apply")
    revisions_path = File.join(a_dir, "revisions.md")
    count_after_first = File.read(revisions_path).scan(/^## Revision v\d+/).length

    Open3.capture2(RbConfig.ruby, RESTORE, a_id, "--at", v1_sha, "--plastic-home", @home, "--apply")
    count_after_second = File.read(revisions_path).scan(/^## Revision v\d+/).length

    assert_equal count_after_first, count_after_second,
      "a true no-op restore (already at v1, nothing left to change) must not append a " \
      "content-free entry; D14 records every ACTUAL change, not every invocation"
  end
end
