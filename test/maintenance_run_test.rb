# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"

require_relative "../scripts/lib/doctor_exclusions"

class MaintenanceRunTest < Minitest::Test
  MAINTENANCE_RUN = File.expand_path("../scripts/maintenance-run", __dir__)

  def setup
    @home = Dir.mktmpdir("plastic-maintenance-run")
    build_fixture_stores
    git("init", "-q", "-b", "main")
    git("add", "-A")
    git("-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "seed fixtures")
  end

  def teardown
    FileUtils.remove_entry(@home) if @home && Dir.exist?(@home)
  end

  # --- fixture builders (mirrors test/project_links_test.rb's write_intent/flow/write_index) ---

  def write_intent(store_dir, basename, id:, intent:, sources:, chain:, links: "## Links\n- legacy placeholder\n")
    dir = File.join(store_dir, basename)
    FileUtils.mkdir_p(dir)
    content = +"---\n"
    content << "id: \"#{id}\"\n"
    content << "intent: \"#{intent}\"\n"
    content << "sources: #{flow(sources)}\n"
    content << "chain: #{flow(chain)}\n"
    content << "created: 2026-06-01\n"
    content << "author: test\n"
    content << "tags: [t]\n"
    content << "---\n\n# #{intent}\n\n## Intent\nBody #{id}.\n\n"
    content << links if links
    File.write(File.join(dir, "#{basename}.md"), content)
  end

  def flow(ids)
    return "[]" if ids.empty?

    "[#{ids.map { |i| "\"#{i}\"" }.join(", ")}]"
  end

  def write_index(path, body = "(none)")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "# Index\n\n## Relocated\n#{body}\n\n## Completed\n")
  end

  # Global: 40 (project-links' cross-store source target for 11).
  # Plastic: 11 sources global:40 (its own ## Links is a stale placeholder - project-links
  # --intent 11 regenerates it, a real change); 12 sources 11 with 11.chain still empty (the
  # I1 backlink rebuild-graph fixes by adding 12 to 11.chain - 11 is the touched id).
  def build_fixture_stores
    global = File.join(@home, "store")
    plastic = File.join(@home, "projects", "plastic", "store")
    [global, plastic].each { |d| FileUtils.mkdir_p(d) }

    write_intent(global, "40--store-graph", id: "40", intent: "Build the store graph",
                 sources: [], chain: [])
    write_intent(plastic, "11--child", id: "11", intent: "Child of forty",
                 sources: ["global:40"], chain: [],
                 links: "## Links\n<!-- Retroactive (intent 60b): heading only. -->\n")
    write_intent(plastic, "12--grandchild", id: "12", intent: "Grandchild",
                 sources: ["11"], chain: [])

    write_index(File.join(@home, "INDEX.md"))
    write_index(File.join(@home, "projects", "plastic", "INDEX.md"))
  end

  def git(*args)
    out, status = Open3.capture2("git", "-C", @home, *args)
    raise "git #{args.join(" ")} failed: #{out}" unless status.success?

    out
  end

  def branches
    out, = Open3.capture3("git", "-C", @home, "branch", "--list")
    out
  end

  def test_defers_when_target_holds_a_fresh_delivery_lock
    # Write a delivery.lock with a fresh mtime in the target intent's directory
    # (JSON shape: {"type":"delivery","owner_session":"other-session", ...}; see
    # scripts/lib/lock.rb's `payload` for the exact keys, or just the minimal
    # {"owner_session":"x"} - Lock.fresh? only checks the file's mtime, not its content).
    lock_path = File.join(@home, "projects", "plastic", "store", "11--child", "delivery.lock")
    File.write(lock_path, '{"owner_session":"someone-else"}')

    out, err, status = Open3.capture3(RbConfig.ruby, MAINTENANCE_RUN, "--tool", "project-links",
                                       "--intent", "11", "--plastic-home", @home, "--apply")
    assert_equal 2, status.exitstatus
    assert_match(/deferred/, out + err)
  end

  def test_applies_project_links_and_merges_when_clean
    out, _err, status = Open3.capture3(RbConfig.ruby, MAINTENANCE_RUN, "--tool", "project-links",
                                        "--intent", "11", "--plastic-home", @home, "--apply")
    assert_equal 0, status.exitstatus, out
    assert_match(/applied and merged/, out)

    log, = Open3.capture3("git", "-C", @home, "log", "--oneline")
    assert_match(/maintenance - project-links --intent 11/, log)
    status_out, = Open3.capture3("git", "-C", @home, "status", "--porcelain")
    assert_empty status_out.strip
    refute_match(/maintenance\//, branches, "no maintenance branch should remain after merge")
  end

  def test_dry_run_makes_no_changes_by_default
    before = File.read(File.join(@home, "projects", "plastic", "store", "11--child", "11--child.md"))
    _out, _err, status = Open3.capture3(RbConfig.ruby, MAINTENANCE_RUN, "--tool", "project-links",
                                         "--intent", "11", "--plastic-home", @home)
    assert_equal 0, status.exitstatus
    assert_equal before, File.read(File.join(@home, "projects", "plastic", "store", "11--child", "11--child.md"))
  end

  def test_project_links_without_intent_is_a_usage_error
    _out, _err, status = Open3.capture3(RbConfig.ruby, MAINTENANCE_RUN, "--tool", "project-links",
                                         "--plastic-home", @home, "--apply")
    assert_equal 1, status.exitstatus
  end

  # FALSIFIABLE (208): an unrelated dirty file elsewhere in the store refuses the WHOLE run
  # (exit 4), rather than being silently swept up or silently ignored.
  def test_refuses_when_store_working_tree_is_dirty
    File.write(File.join(@home, "unrelated.md"), "dirty\n")
    _out, _err, status = Open3.capture3(RbConfig.ruby, MAINTENANCE_RUN, "--tool", "project-links",
                                         "--intent", "11", "--plastic-home", @home, "--apply")
    assert_equal 4, status.exitstatus
  end

  # 12 sources 11 while 11.chain is still empty: rebuild-graph's I1 pass writes the missing
  # backlink into 11's own frontmatter, so 11 is the touched id (mirrors
  # test/rebuild_graph_test.rb's "22c.chain += 80" shape). A fresh lock on 11 must defer the
  # WHOLE rebuild-graph run, never partially apply around it.
  def test_rebuild_graph_defers_when_any_touched_id_holds_a_fresh_lock
    lock_path = File.join(@home, "projects", "plastic", "store", "11--child", "delivery.lock")
    File.write(lock_path, '{"owner_session":"someone-else"}')

    out, err, status = Open3.capture3(RbConfig.ruby, MAINTENANCE_RUN, "--tool", "rebuild-graph",
                                       "--plastic-home", @home, "--apply")
    assert_equal 2, status.exitstatus
    assert_match(/deferred/, out + err)
    refute_match(/maintenance\/rebuild-graph-/, branches, "no branch should be created on defer")
  end

  # FALSIFIABLE (208) and load-bearing for Task 13: real proof-case ids (26, 15) collide
  # across stores. An ambiguous --intent with no --store must abort (exit 1, a usage-shaped
  # failure, distinct from 2/3/4) rather than silently regenerate the WRONG store's intent.
  def test_ambiguous_intent_across_stores_aborts_without_store_flag
    knowdb = File.join(@home, "projects", "knowdb", "store")
    FileUtils.mkdir_p(File.join(knowdb, "11--knowdb-collision"))
    File.write(File.join(knowdb, "11--knowdb-collision", "11--knowdb-collision.md"),
               "---\nid: \"11\"\nintent: t\nsources: []\nchain: []\ncreated: 2026-06-01\n" \
               "author: t\ntags: [t]\n---\n\n## Intent\nb\n")
    FileUtils.mkdir_p(File.join(@home, "projects", "knowdb"))
    File.write(File.join(@home, "projects", "knowdb", "INDEX.md"), "# Index\n\n## Completed\n")
    Open3.capture3("git", "-C", @home, "add", "-A")
    Open3.capture3("git", "-C", @home, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "add collision")

    _out, err, status = Open3.capture3(RbConfig.ruby, MAINTENANCE_RUN, "--tool", "project-links",
                                        "--intent", "11", "--plastic-home", @home, "--apply")
    assert_equal 1, status.exitstatus
    assert_match(/ambiguous/, err)
  end

  def test_store_flag_disambiguates_and_applies_to_the_named_store_only
    knowdb = File.join(@home, "projects", "knowdb", "store")
    FileUtils.mkdir_p(File.join(knowdb, "11--knowdb-collision"))
    File.write(File.join(knowdb, "11--knowdb-collision", "11--knowdb-collision.md"),
               "---\nid: \"11\"\nintent: t\nsources: []\nchain: []\ncreated: 2026-06-01\n" \
               "author: t\ntags: [t]\n---\n\n## Intent\nb\n")
    FileUtils.mkdir_p(File.join(@home, "projects", "knowdb"))
    File.write(File.join(@home, "projects", "knowdb", "INDEX.md"), "# Index\n\n## Completed\n")
    Open3.capture3("git", "-C", @home, "add", "-A")
    Open3.capture3("git", "-C", @home, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "add collision")

    before_knowdb = File.read(File.join(knowdb, "11--knowdb-collision", "11--knowdb-collision.md"))

    _out, _err, status = Open3.capture3(RbConfig.ruby, MAINTENANCE_RUN, "--tool", "project-links",
                                         "--intent", "11", "--store", "project:plastic",
                                         "--plastic-home", @home, "--apply")
    assert_equal 0, status.exitstatus

    assert_equal before_knowdb, File.read(File.join(knowdb, "11--knowdb-collision", "11--knowdb-collision.md")),
      "the --store-excluded knowdb intent 11 must be untouched"
  end

  # --- rebuild-savepoint (intent 211, D7): dry-run default, refuses without a real outcome.md,
  # composes Savepoint.rebuild_savepoint + Savepoint.append_terminal_savepoint inside one scoped commit ---

  def write_outcome(dir, disposition: "delivered")
    File.write(File.join(dir, "outcome.md"),
               "---\ndisposition: #{disposition}\n---\n\n# Outcome\n\nDelivered.\n")
  end

  def test_rebuild_savepoint_requires_intent_flag
    _out, _err, status = Open3.capture3(RbConfig.ruby, MAINTENANCE_RUN, "--tool", "rebuild-savepoint",
                                         "--plastic-home", @home, "--apply")
    assert_equal 1, status.exitstatus
  end

  def test_rebuild_savepoint_dry_run_reports_intended_reconstruction_without_writing
    dir = File.join(@home, "projects", "plastic", "store", "11--child")
    write_outcome(dir)
    savepoint_path = File.join(dir, "savepoint.md")
    refute File.exist?(savepoint_path)

    out, _err, status = Open3.capture3(RbConfig.ruby, MAINTENANCE_RUN, "--tool", "rebuild-savepoint",
                                        "--intent", "11", "--store", "project:plastic",
                                        "--plastic-home", @home)
    assert_equal 0, status.exitstatus, out
    assert_match(/DRY RUN/, out)
    refute File.exist?(savepoint_path), "dry-run must not write savepoint.md"
  end

  def test_rebuild_savepoint_applies_and_appends_one_revisions_entry
    dir = File.join(@home, "projects", "plastic", "store", "11--child")
    write_outcome(dir)
    git("add", "-A")
    git("-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "seed outcome fixture")

    out, _err, status = Open3.capture3(RbConfig.ruby, MAINTENANCE_RUN, "--tool", "rebuild-savepoint",
                                        "--intent", "11", "--store", "project:plastic",
                                        "--plastic-home", @home, "--apply")
    assert_equal 0, status.exitstatus, out
    assert_match(/applied and merged/, out)

    savepoint = File.read(File.join(dir, "savepoint.md"))
    assert_match(/\bDone\b.*\bdelivered\b/, savepoint)

    revisions = File.read(File.join(dir, "revisions.md"))
    assert_equal 1, revisions.scan(/^## Revision v\d+/).size
    assert_match(/savepoint-operational-reconstruction/, revisions)

    status_out, = Open3.capture3("git", "-C", @home, "status", "--porcelain")
    assert_empty status_out.strip
  end

  def test_rebuild_savepoint_refuses_when_outcome_missing
    dir = File.join(@home, "projects", "plastic", "store", "11--child")
    refute File.exist?(File.join(dir, "outcome.md"))

    _out, err, status = Open3.capture3(RbConfig.ruby, MAINTENANCE_RUN, "--tool", "rebuild-savepoint",
                                        "--intent", "11", "--store", "project:plastic",
                                        "--plastic-home", @home, "--apply")
    assert_equal 1, status.exitstatus
    assert_match(/outcome\.md is missing or a placeholder/, err)
    refute File.exist?(File.join(dir, "savepoint.md"))
  end

  def test_rebuild_savepoint_refuses_when_outcome_is_a_placeholder
    dir = File.join(@home, "projects", "plastic", "store", "11--child")
    File.write(File.join(dir, "outcome.md"), "<!-- plastic:placeholder -->\n")

    _out, err, status = Open3.capture3(RbConfig.ruby, MAINTENANCE_RUN, "--tool", "rebuild-savepoint",
                                        "--intent", "11", "--store", "project:plastic",
                                        "--plastic-home", @home)
    assert_equal 1, status.exitstatus
    assert_match(/outcome\.md is missing or a placeholder/, err)
  end

  def test_rebuild_savepoint_defers_when_target_holds_a_fresh_delivery_lock
    dir = File.join(@home, "projects", "plastic", "store", "11--child")
    write_outcome(dir)
    File.write(File.join(dir, "delivery.lock"), '{"owner_session":"someone-else"}')

    out, err, status = Open3.capture3(RbConfig.ruby, MAINTENANCE_RUN, "--tool", "rebuild-savepoint",
                                       "--intent", "11", "--store", "project:plastic",
                                       "--plastic-home", @home, "--apply")
    assert_equal 2, status.exitstatus
    assert_match(/deferred/, out + err)
  end

  # --- register-exclusions (intent 274, spec D7/D8): computes violations through Doctor's
  # OWN done_signal_findings_for_dir, unions with any pre-existing hand-added file content,
  # skips a fresh-locked intent rather than aborting, writes ALL stores in one scoped commit,
  # and writes no revisions.md entries (it edits no intent directory, only a store-level table).

  # A doctor-shaped INDEX.md (## Active/Future/Clusters/Abandoned/Completed), distinct from
  # this file's project-links-shaped write_index: register-exclusions walks the SAME
  # index_sections_by_dir doctor itself uses, so the fixture must carry real section headers.
  def write_doctor_index(path, completed_dirnames: [])
    body = +"# Index\n\n## Active\n\n## Future\n\n## Clusters\n\n## Abandoned\n\n## Completed\n"
    completed_dirnames.each do |dirname|
      id = dirname.split("--", 2).first
      body << "- [#{id} — t](store/#{dirname}/#{dirname}.md) — t\n"
    end
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
  end

  # Marks the fixture's global "40--store-graph" and plastic-project "11--child" Completed
  # (both already lack savepoint.md, so both are real savepoint_operational violations), and
  # gitignores *.lock the way a real ~/.plastic install does (scripts/lib/lock.rb), so a
  # written-but-uncommitted delivery.lock never trips MaintenanceGit's clean-tree precondition.
  def seed_register_exclusions_fixture
    File.write(File.join(@home, ".gitignore"), "*.lock\n")
    write_doctor_index(File.join(@home, "INDEX.md"), completed_dirnames: ["40--store-graph"])
    write_doctor_index(File.join(@home, "projects", "plastic", "INDEX.md"), completed_dirnames: ["11--child"])
    git("add", "-A")
    git("-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "seed register-exclusions fixture")
  end

  def test_register_exclusions_dry_run_writes_nothing
    seed_register_exclusions_fixture

    out, _err, status = Open3.capture3(RbConfig.ruby, MAINTENANCE_RUN, "--tool", "register-exclusions",
                                        "--plastic-home", @home)
    assert_equal 0, status.exitstatus, out
    refute File.exist?(File.join(@home, "doctor-exclusions"))
    refute File.exist?(File.join(@home, "projects", "plastic", "doctor-exclusions"))
  end

  def test_register_exclusions_dry_run_names_scope_and_ids
    seed_register_exclusions_fixture

    out, _err, status = Open3.capture3(RbConfig.ruby, MAINTENANCE_RUN, "--tool", "register-exclusions",
                                        "--plastic-home", @home)
    assert_equal 0, status.exitstatus, out
    assert_match(/global/, out)
    assert_match(/\b40\b/, out)
    assert_match(/project:plastic/, out)
    assert_match(/\b11\b/, out)
  end

  def test_register_exclusions_bad_rule_is_a_usage_error
    seed_register_exclusions_fixture

    _out, err, status = Open3.capture3(RbConfig.ruby, MAINTENANCE_RUN, "--tool", "register-exclusions",
                                        "--rule", "bogus", "--plastic-home", @home)
    assert_equal 1, status.exitstatus
    assert_match(/not excludable/, err)
    assert_match(/savepoint_operational/, err)
  end

  def test_register_exclusions_apply_writes_and_commits_once_across_stores
    seed_register_exclusions_fixture

    out, _err, status = Open3.capture3(RbConfig.ruby, MAINTENANCE_RUN, "--tool", "register-exclusions",
                                        "--plastic-home", @home, "--apply")
    assert_equal 0, status.exitstatus, out

    global_loaded = DoctorExclusions.load(File.join(@home, "INDEX.md"))
    assert_empty global_loaded[:errors]
    assert_equal ["40"], global_loaded[:rules]["savepoint_operational"]

    plastic_loaded = DoctorExclusions.load(File.join(@home, "projects", "plastic", "INDEX.md"))
    assert_empty plastic_loaded[:errors]
    assert_equal ["11"], plastic_loaded[:rules]["savepoint_operational"]

    log, = Open3.capture3("git", "-C", @home, "log", "--oneline")
    assert_equal 1, log.lines.count { |l| l =~ /register doctor exclusions/ }

    status_out, = Open3.capture3("git", "-C", @home, "status", "--porcelain")
    assert_empty status_out.strip
  end

  def test_register_exclusions_unions_with_a_preexisting_hand_added_id
    seed_register_exclusions_fixture
    File.write(File.join(@home, "doctor-exclusions"), "savepoint_operational 999\n")
    git("add", "-A")
    git("-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "hand-add 999")

    out, _err, status = Open3.capture3(RbConfig.ruby, MAINTENANCE_RUN, "--tool", "register-exclusions",
                                        "--plastic-home", @home, "--apply")
    assert_equal 0, status.exitstatus, out

    loaded = DoctorExclusions.load(File.join(@home, "INDEX.md"))
    assert_equal ["40", "999"], loaded[:rules]["savepoint_operational"].sort
  end

  # Review F2 regression: render_exclusions_file rebuilds the rule lines from parsed rules on
  # every run, which would otherwise silently discard a hand-written file's comment lines -
  # under D8 this tool writes no revisions.md receipt, so a comment is the only home for an
  # exemption's justification, and losing it on the next --apply would be a real data loss.
  def test_register_exclusions_preserves_hand_written_comments_on_apply
    seed_register_exclusions_fixture
    hand_written = "# 999 is exempt: pre-convention intent, no real outcome.md ever existed\n" \
                   "# approved by owner 2026-08-01\n" \
                   "savepoint_operational 999\n"
    File.write(File.join(@home, "doctor-exclusions"), hand_written)
    git("add", "-A")
    git("-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "hand-add 999 with comments")

    out, _err, status = Open3.capture3(RbConfig.ruby, MAINTENANCE_RUN, "--tool", "register-exclusions",
                                        "--plastic-home", @home, "--apply")
    assert_equal 0, status.exitstatus, out

    content = File.read(File.join(@home, "doctor-exclusions"))
    assert_includes content, "# 999 is exempt: pre-convention intent, no real outcome.md ever existed\n"
    assert_includes content, "# approved by owner 2026-08-01\n"

    loaded = DoctorExclusions.load(File.join(@home, "INDEX.md"))
    assert_equal ["40", "999"], loaded[:rules]["savepoint_operational"].sort
  end

  # Review F5 regression: render_exclusions_file's caller reads the existing file with a raw
  # File.read, separate from DoctorExclusions.load's own internal scrub, so a byte invalid in
  # the file's declared encoding raised Encoding::CompatibilityError in BOTH dry-run and
  # --apply, even though `existing` (loaded via DoctorExclusions.load) already reported that
  # same file clean. Reproduced first (both modes raised at maintenance-run's
  # render_exclusions_file line-scan), then fixed by scrubbing that raw read too.
  def test_register_exclusions_never_raises_on_an_invalid_byte_in_an_existing_comment
    seed_register_exclusions_fixture
    File.binwrite(File.join(@home, "doctor-exclusions"),
                  "# a comment with a bad byte caf\xE9\nsavepoint_operational 999\n")
    git("add", "-A")
    git("-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "seed bad-byte comment fixture")

    dry_out, _err, dry_status = Open3.capture3(RbConfig.ruby, MAINTENANCE_RUN, "--tool", "register-exclusions",
                                                "--plastic-home", @home)
    assert_equal 0, dry_status.exitstatus, dry_out

    out, _err, status = Open3.capture3(RbConfig.ruby, MAINTENANCE_RUN, "--tool", "register-exclusions",
                                        "--plastic-home", @home, "--apply")
    assert_equal 0, status.exitstatus, out

    content = File.read(File.join(@home, "doctor-exclusions"))
    assert_includes content, "a comment with a bad byte caf"

    loaded = DoctorExclusions.load(File.join(@home, "INDEX.md"))
    assert_equal ["40", "999"], loaded[:rules]["savepoint_operational"].sort
  end

  def test_register_exclusions_writes_no_revisions_entries
    seed_register_exclusions_fixture

    out, _err, status = Open3.capture3(RbConfig.ruby, MAINTENANCE_RUN, "--tool", "register-exclusions",
                                        "--plastic-home", @home, "--apply")
    assert_equal 0, status.exitstatus, out

    refute File.exist?(File.join(@home, "store", "40--store-graph", "revisions.md"))
    refute File.exist?(File.join(@home, "projects", "plastic", "store", "11--child", "revisions.md"))
  end

  def test_register_exclusions_skips_a_fresh_locked_intent_and_still_exits_zero
    seed_register_exclusions_fixture
    File.write(File.join(@home, "store", "40--store-graph", "delivery.lock"),
               '{"owner_session":"someone-else"}')

    out, _err, status = Open3.capture3(RbConfig.ruby, MAINTENANCE_RUN, "--tool", "register-exclusions",
                                        "--plastic-home", @home, "--apply")
    assert_equal 0, status.exitstatus, out
    assert_match(/40--store-graph skipped/, out)

    global_loaded = DoctorExclusions.load(File.join(@home, "INDEX.md"))
    refute_includes(global_loaded[:rules]["savepoint_operational"] || [], "40")
  end

  # --- register-exclusions --prune (intent 280): removes exactly the rows DoctorExclusions.dead_rows
  # reports as suppressing nothing, through the same walk, the same comment-preserving writer,
  # and the same dry-run/--apply gate as the add direction.

  def commit_all(message)
    git("add", "-A")
    git("-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", message)
  end

  def test_prune_dry_run_writes_nothing
    seed_register_exclusions_fixture
    File.write(File.join(@home, "doctor-exclusions"), "savepoint_operational 40 999\n")
    commit_all("seed dead row fixture")
    before = File.read(File.join(@home, "doctor-exclusions"))

    out, _err, status = Open3.capture3(RbConfig.ruby, MAINTENANCE_RUN, "--tool", "register-exclusions",
                                        "--prune", "--plastic-home", @home)
    assert_equal 0, status.exitstatus, out
    assert_equal before, File.read(File.join(@home, "doctor-exclusions"))
    assert_match(/DRY RUN/, out)
    assert_match(/999/, out)
  end

  def test_prune_apply_removes_exactly_the_dead_rows
    seed_register_exclusions_fixture
    File.write(File.join(@home, "doctor-exclusions"), "savepoint_operational 40 999\n")
    commit_all("seed dead row fixture")

    out, _err, status = Open3.capture3(RbConfig.ruby, MAINTENANCE_RUN, "--tool", "register-exclusions",
                                        "--prune", "--plastic-home", @home, "--apply")
    assert_equal 0, status.exitstatus, out

    loaded = DoctorExclusions.load(File.join(@home, "INDEX.md"))
    assert_empty loaded[:errors]
    assert_equal ["40"], loaded[:rules]["savepoint_operational"]
  end

  # Mirrors test_register_exclusions_preserves_hand_written_comments_on_apply (F2), prune direction.
  def test_prune_preserves_hand_written_comments
    seed_register_exclusions_fixture
    hand_written = "# 999 is exempt: pre-convention intent, no real outcome.md ever existed\n" \
                   "# approved by owner 2026-08-01\n" \
                   "savepoint_operational 40 999\n"
    File.write(File.join(@home, "doctor-exclusions"), hand_written)
    commit_all("hand-add 999 with comments")

    out, _err, status = Open3.capture3(RbConfig.ruby, MAINTENANCE_RUN, "--tool", "register-exclusions",
                                        "--prune", "--plastic-home", @home, "--apply")
    assert_equal 0, status.exitstatus, out

    content = File.read(File.join(@home, "doctor-exclusions"))
    assert_includes content, "# 999 is exempt: pre-convention intent, no real outcome.md ever existed\n"
    assert_includes content, "# approved by owner 2026-08-01\n"

    loaded = DoctorExclusions.load(File.join(@home, "INDEX.md"))
    assert_equal ["40"], loaded[:rules]["savepoint_operational"]
  end

  # D6: a fresh delivery lock on the registered intent's own dir leaves it out of BOTH consumed
  # and known_ids in the walk, which would otherwise read as dead. The lock skip must hold it
  # harmless rather than prune it.
  def test_prune_never_removes_an_id_whose_intent_holds_a_fresh_lock
    seed_register_exclusions_fixture
    File.write(File.join(@home, "doctor-exclusions"), "savepoint_operational 40\n")
    commit_all("seed exclusion for 40")
    File.write(File.join(@home, "store", "40--store-graph", "delivery.lock"),
               '{"owner_session":"someone-else"}')

    out, _err, status = Open3.capture3(RbConfig.ruby, MAINTENANCE_RUN, "--tool", "register-exclusions",
                                        "--prune", "--plastic-home", @home, "--apply")
    assert_equal 0, status.exitstatus, out
    assert_match(/40--store-graph skipped/, out)

    loaded = DoctorExclusions.load(File.join(@home, "INDEX.md"))
    assert_equal ["40"], loaded[:rules]["savepoint_operational"]
  end

  # D6a: savepoint_operational only fires on a terminal intent, so a row naming a live
  # non-terminal (## Active) intent has nothing to suppress YET. Prune must leave it and name it
  # as kept, distinct from D6's lock-skip wording.
  def test_prune_never_removes_an_id_whose_intent_is_not_terminal
    seed_register_exclusions_fixture
    plastic_index = File.join(@home, "projects", "plastic", "INDEX.md")
    body = +"# Index\n\n## Active\n- [12 — t](store/12--grandchild/12--grandchild.md) — t\n\n" \
           "## Future\n\n## Clusters\n\n## Abandoned\n\n## Completed\n" \
           "- [11 — t](store/11--child/11--child.md) — t\n"
    File.write(plastic_index, body)
    File.write(File.join(@home, "projects", "plastic", "doctor-exclusions"), "savepoint_operational 11 12\n")
    commit_all("seed non-terminal exclusion")

    out, _err, status = Open3.capture3(RbConfig.ruby, MAINTENANCE_RUN, "--tool", "register-exclusions",
                                        "--prune", "--plastic-home", @home, "--apply")
    assert_equal 0, status.exitstatus, out
    assert_match(/12 kept \(protected, still live\)/, out)

    loaded = DoctorExclusions.load(plastic_index)
    assert_includes loaded[:rules]["savepoint_operational"], "12"
  end

  # D7: a rule left with zero ids after pruning is dropped from the file entirely, rather than
  # rendered as a bare `rule_name` line - DoctorExclusions.parse rejects that shape outright.
  def test_prune_drops_a_rule_whose_ids_are_all_dead
    seed_register_exclusions_fixture
    File.write(File.join(@home, "doctor-exclusions"), "savepoint_operational 999\n")
    commit_all("seed all-dead rule fixture")

    out, _err, status = Open3.capture3(RbConfig.ruby, MAINTENANCE_RUN, "--tool", "register-exclusions",
                                        "--prune", "--plastic-home", @home, "--apply")
    assert_equal 0, status.exitstatus, out

    content = File.read(File.join(@home, "doctor-exclusions"))
    refute_match(/^savepoint_operational\s*$/, content)

    loaded = DoctorExclusions.load(File.join(@home, "INDEX.md"))
    assert_empty loaded[:errors]
    refute loaded[:rules].key?("savepoint_operational")
  end

  # D8 restated for the prune direction: no revisions.md entries anywhere, since this tool
  # modifies no intent directory, only a store-level table.
  def test_prune_writes_no_revisions_entries
    seed_register_exclusions_fixture
    File.write(File.join(@home, "doctor-exclusions"), "savepoint_operational 40 999\n")
    commit_all("seed dead row fixture")

    out, _err, status = Open3.capture3(RbConfig.ruby, MAINTENANCE_RUN, "--tool", "register-exclusions",
                                        "--prune", "--plastic-home", @home, "--apply")
    assert_equal 0, status.exitstatus, out

    refute File.exist?(File.join(@home, "store", "40--store-graph", "revisions.md"))
    refute File.exist?(File.join(@home, "projects", "plastic", "store", "11--child", "revisions.md"))
  end

  def test_prune_with_nothing_dead_exits_zero_and_writes_nothing
    seed_register_exclusions_fixture
    File.write(File.join(@home, "doctor-exclusions"), "savepoint_operational 40\n")
    commit_all("seed live-only exclusion")
    before = File.read(File.join(@home, "doctor-exclusions"))

    out, _err, status = Open3.capture3(RbConfig.ruby, MAINTENANCE_RUN, "--tool", "register-exclusions",
                                        "--prune", "--plastic-home", @home, "--apply")
    assert_equal 0, status.exitstatus, out
    assert_match(/no dead savepoint_operational exclusion rows to prune/, out)
    assert_equal before, File.read(File.join(@home, "doctor-exclusions"))
  end

  # REGRESSION (post-review fix item 1): "70--ghost" has a REAL directory on disk under the
  # global store but is never referenced anywhere in INDEX.md - a de-indexed "ghost". The buggy
  # v1 predicate derived known_ids from index_sections_by_dir walk membership alone, so this
  # exact fixture (registered, on disk, absent from INDEX) got silently pruned: the file was
  # rewritten to drop "70" even though its directory plainly still existed, a silent loss of a
  # governance row that is its own only audit trail (D8 - no revisions.md receipt exists for
  # this tool). The fix resolves known_ids against a direct scan of the store's own directory
  # listing, and separately protects any id in that gap via protected_ids as defense-in-depth.
  def test_prune_never_removes_an_id_with_a_real_directory_absent_from_index
    seed_register_exclusions_fixture
    ghost_dir = File.join(@home, "store", "70--ghost")
    FileUtils.mkdir_p(ghost_dir)
    File.write(File.join(@home, "doctor-exclusions"), "savepoint_operational 40 70\n")
    commit_all("seed ghost-directory fixture")

    out, _err, status = Open3.capture3(RbConfig.ruby, MAINTENANCE_RUN, "--tool", "register-exclusions",
                                        "--prune", "--plastic-home", @home, "--apply")
    assert_equal 0, status.exitstatus, out

    loaded = DoctorExclusions.load(File.join(@home, "INDEX.md"))
    assert_includes loaded[:rules]["savepoint_operational"], "70",
      "an id whose directory genuinely exists, just unindexed, must survive prune"
    assert_includes loaded[:rules]["savepoint_operational"], "40",
      "the genuinely live id (a real, unregistered-elsewhere gap) must also survive"
    assert File.directory?(ghost_dir), "the ghost directory itself must be left untouched"
  end

  # REGRESSION (post-review fix item 1, third pass): the prune walk only ever evaluates
  # savepoint_operational's own finding bucket, regardless of --rule - reproduced by the reviewer
  # with a scratch second EXCLUDABLE_CHECKS entry, which is otherwise unreachable in v1 (exactly
  # one excludable rule). Passing --prune --rule <scratch> without the guard computed found_ids
  # from the unrelated savepoint_operational check and subtracted it against <scratch>'s own
  # registered ids, misreporting every one of them dead and rewriting the file to drop them.
  #
  # This test reproduces the scratch catalog entry the same way the reviewer did, but against an
  # ISOLATED COPY of scripts/ in a tmpdir rather than the real, shared, git-tracked
  # rule_catalog.rb - maintenance-run runs as a real subprocess (Open3), so an in-process
  # monkeypatch of the frozen EXCLUDABLE_CHECKS constant would never reach it, and patching the
  # actual checked-out file on disk would risk colliding with any other concurrent process
  # reading it.
  def test_prune_refuses_a_rule_the_walk_does_not_evaluate
    parent = Dir.mktmpdir("scratch-rule-scripts")
    FileUtils.cp_r(File.expand_path("../scripts", __dir__), parent)
    scripts_copy = File.join(parent, "scripts")
    catalog_path = File.join(scripts_copy, "lib", "rule_catalog.rb")
    original = File.read(catalog_path)
    scratch = original.sub(
      "\"savepoint_operational\" =>",
      "\"scratch_rule\" => \"test-only scratch entry, never a real doctor check\",\n    " \
      "\"savepoint_operational\" =>"
    )
    raise "scratch catalog patch made no change" if scratch == original
    File.write(catalog_path, scratch)
    maintenance_run_copy = File.join(scripts_copy, "maintenance-run")

    seed_register_exclusions_fixture
    File.write(File.join(@home, "doctor-exclusions"), "scratch_rule 40\n")
    commit_all("seed scratch-rule fixture")
    # Compared as raw bytes below, not via DoctorExclusions.load: THIS test process still has the
    # real, unpatched RuleCatalog in memory (loaded once at file-require time), which does not
    # know "scratch_rule" is excludable - only the isolated subprocess copy does.
    before = File.read(File.join(@home, "doctor-exclusions"))

    out, err, status = Open3.capture3(RbConfig.ruby, maintenance_run_copy, "--tool", "register-exclusions",
                                       "--rule", "scratch_rule", "--prune", "--plastic-home", @home, "--apply")
    assert_equal 1, status.exitstatus, out + err
    assert_match(/prune evaluates only savepoint_operational/, err)
    assert_equal before, File.read(File.join(@home, "doctor-exclusions")),
      "the file must be byte-unchanged when --prune refuses"
  ensure
    FileUtils.remove_entry(parent) if parent && Dir.exist?(parent)
  end
end
