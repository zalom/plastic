# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
require "rbconfig"

require_relative "../scripts/lib/savepoint"
require_relative "../scripts/lib/node_ledger"
require_relative "../scripts/lib/intent_screen"
require_relative "../scripts/doctor"
require_relative "../scripts/lib/roadmap_savepoint"
require_relative "../scripts/lib/guarded_append"

# Intent 335 (G2), S4: ledger co-existence. Matrix rows 4.1-4.16 in
# actions/ACTION_1.md. The existing stage ledger, its readers, its rebuild, and its
# phantom detector must keep working unchanged BESIDE the new transition lines.
class LedgerCoexistenceTest < Minitest::Test
  REPO = File.expand_path("..", __dir__)

  def setup
    @home = Dir.mktmpdir("ledger-coexistence")
    @store = File.join(@home, "store")
    @dir = File.join(@store, "1--demo")
    FileUtils.mkdir_p(@dir)
    File.write(File.join(@dir, "1--demo.md"), "---\nid: \"1\"\nintent: \"t\"\n---\n\n## Intent\nbody\n")
    File.write(File.join(@home, "INDEX.md"), "# Index\n\n## Relocated\n(none)\n\n## Completed\n")
  end

  def teardown
    FileUtils.remove_entry(@home) if @home && Dir.exist?(@home)
  end

  def savepoint_path
    File.join(@dir, "savepoint.md")
  end

  def write_savepoint(content)
    File.write(savepoint_path, content)
  end

  def transition_line(subject:, state:, fields: {}, comment: nil, now: Time.utc(2026, 9, 8, 12, 0, 0))
    NodeLedger.transition_line(subject: subject, state: state, fields: fields, comment: comment, now: now)
  end

  # --- 4.1-4.5: rebuild -----------------------------------------------------------

  def test_rebuild_preserves_every_transition_line
    File.write(File.join(@dir, "spec.md"), "# Spec\n")
    write_savepoint(
      "2026-07-01T00:00:00Z  What  1--demo.md\n" \
      "2026-07-01T00:01:00Z  Why  spec.md created\n" +
      transition_line(subject: "n1", state: "planned")
    )
    count = Savepoint.rebuild_savepoint(@dir)
    content = File.read(savepoint_path)
    assert_match(/n1  planned/, content)
    assert_equal count, content.each_line.count
  end

  def test_rebuild_preserves_transition_line_relative_order
    l1 = transition_line(subject: "n1", state: "planned", now: Time.utc(2026, 9, 8, 10, 0, 0))
    l2 = transition_line(subject: "n1", state: "running",
                          fields: { holder: "x", expires: "2026-09-08T11:00:00Z", packet: "p", model: "sonnet" },
                          now: Time.utc(2026, 9, 8, 10, 5, 0))
    l3 = transition_line(subject: "n1", state: "done", fields: { gates: "suite", commit: "abc" },
                          now: Time.utc(2026, 9, 8, 10, 10, 0))
    write_savepoint("2026-07-01T00:00:00Z  What  1--demo.md\n" + l1 + l2 + l3)
    Savepoint.rebuild_savepoint(@dir)
    content = File.read(savepoint_path)
    positions = [l1, l2, l3].map { |l| content.index(l.chomp) }
    assert_equal positions, positions.sort, "transition lines must keep their original relative order"
  end

  def test_rebuild_still_works_on_a_stage_only_ledger
    File.write(File.join(@dir, "spec.md"), "# Spec\n")
    write_savepoint("2026-07-01T00:00:00Z  What  1--demo.md\n2026-07-01T00:01:00Z  Why  spec.md created\n")
    count = Savepoint.rebuild_savepoint(@dir)
    content = File.read(savepoint_path)
    assert_equal 2, count
    assert_match(/What  1--demo\.md/, content)
    assert_match(/Why  spec\.md created/, content)
  end

  def test_rebuild_returns_the_total_line_count_including_preserved_lines
    File.write(File.join(@dir, "spec.md"), "# Spec\n")
    write_savepoint(
      "2026-07-01T00:00:00Z  What  1--demo.md\n2026-07-01T00:01:00Z  Why  spec.md created\n" +
      transition_line(subject: "n1", state: "planned") +
      transition_line(subject: "n2", state: "planned")
    )
    count = Savepoint.rebuild_savepoint(@dir)
    assert_equal 4, count
    assert_equal 4, File.read(savepoint_path).each_line.count
  end

  def test_maintenance_run_rebuild_preserves_transition_lines
    maintenance_run = File.join(REPO, "scripts", "maintenance-run")
    home = Dir.mktmpdir("maintenance-rebuild")
    begin
      dir = File.join(home, "store", "1--demo")
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, "1--demo.md"), "---\nid: \"1\"\nintent: \"t\"\n---\n\n## Intent\nbody\n")
      File.write(File.join(dir, "outcome.md"), "---\ndisposition: delivered\n---\n\n# Outcome\n\nDone.\n")
      File.write(File.join(dir, "savepoint.md"), transition_line(subject: "n1", state: "planned"))
      File.write(File.join(home, "INDEX.md"), "# Index\n\n## Relocated\n(none)\n\n## Completed\n")

      Open3.capture3("git", "-C", home, "init", "-q", "-b", "main")
      Open3.capture3("git", "-C", home, "add", "-A")
      Open3.capture3("git", "-C", home, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "seed")

      out, err, status = Open3.capture3(RbConfig.ruby, maintenance_run, "--tool", "rebuild-savepoint",
                                         "--intent", "1", "--plastic-home", home, "--apply")
      assert_equal 0, status.exitstatus, out + err
      content = File.read(File.join(dir, "savepoint.md"))
      assert_match(/n1  planned/, content)
    ensure
      FileUtils.remove_entry(home) if Dir.exist?(home)
    end
  end

  # --- 4.6-4.7: phantom detector ---------------------------------------------------

  def test_repeated_transition_lines_are_not_phantoms
    line = transition_line(subject: "n2", state: "planned")
    write_savepoint("2026-07-01T00:00:00Z  What  1--demo.md\n" + line + line)
    phantoms = Savepoint.savepoint_phantom_lines(@dir)
    refute phantoms.any? { |l, _reason| l.include?("n2  planned") },
      "two identical transition lines must never be flagged as a duplicate phantom"
  end

  def test_stage_phantom_detection_is_unchanged
    write_savepoint(
      "2026-07-01T00:00:00Z  What  1--demo.md\n" \
      "2026-07-01T00:01:00Z  Why  spec.md created\n" \
      "2026-07-01T00:02:00Z  Why  spec.md created\n"
    )
    phantoms = Savepoint.savepoint_phantom_lines(@dir)
    assert phantoms.any? { |l, reason| l.include?("Why  spec.md created") && reason.include?("duplicate") }
  end

  # --- 4.8-4.10: stage pick and screen render (pins) -------------------------------

  def test_the_stage_pick_ignores_transition_lines
    write_savepoint(
      "2026-07-01T00:00:00Z  What  1--demo.md\n" \
      "2026-07-01T00:01:00Z  Why  spec.md created\n" +
      transition_line(subject: "n1", state: "running",
                       fields: { holder: "x", expires: "2026-09-08T11:00:00Z", packet: "p", model: "sonnet" })
    )
    fields = IntentScreen.savepoint_fields(@dir, "")
    assert_equal "How", fields["stage"]
  end

  def test_lifecycle_line_rejects_a_transition_line
    refute IntentScreen.lifecycle_line?("2026-09-08T12:00:00Z  n1  running holder=x")
    refute IntentScreen.lifecycle_line?("2026-09-08T12:00:00Z  Intent  needs_decision question=\"q?\"")
    assert IntentScreen.lifecycle_line?("2026-09-08T12:00:00Z  Why  spec.md created")
  end

  def test_a_transition_line_renders_whole_as_the_savepoint_field
    line = transition_line(subject: "n1", state: "running",
                            fields: { holder: "x", expires: "2026-09-08T11:00:00Z", packet: "p", model: "sonnet" })
    write_savepoint("2026-07-01T00:00:00Z  What  1--demo.md\n" + line)
    fields = IntentScreen.savepoint_fields(@dir, "")
    assert_match(/holder=x/, fields["savepoint"])
    assert_match(/expires=2026-09-08T11:00:00Z/, fields["savepoint"])
  end

  # --- 4.11-4.13: doctor ------------------------------------------------------------

  def doctor(plastic_home: @home) = Doctor.new(plastic_home: plastic_home)

  def find(checks, name) = checks.find { |c| c[:name] == name }

  def write_full_lifecycle(id: "1")
    File.write(File.join(@dir, "spec.md"), "# Spec\n")
    File.write(File.join(@dir, "plan.md"), "# Plan\n")
    File.write(File.join(@dir, "checklist.md"), "# Checklist\n\n- [x] done\n")
    File.write(File.join(@dir, "outcome.md"), "---\ndisposition: delivered\n---\n\n# Outcome\n\nDone.\n")
  end

  def test_doctor_reports_torn_and_unattributed_transition_lines
    write_savepoint(
      "2026-07-01T00:00:00Z  What  1--demo.md\n" \
      "2026-09-08T12:00:00Z  n1  running holder=auto-ce5\n" # torn: missing expires/packet/model
    )
    checks = doctor.check_intent_end("1")
    result = find(checks, "intent_savepoint_truthful")
    assert_equal "warn", result[:status]
    assert_match(/torn/, result[:message] + result[:details].to_s)
  end

  def test_doctor_passes_on_a_clean_graph_ledger
    write_savepoint(
      "2026-07-01T00:00:00Z  What  1--demo.md\n" +
      transition_line(subject: "n1", state: "running",
                       fields: { holder: "x", expires: "2026-09-08T11:00:00Z", packet: "p", model: "sonnet" })
    )
    checks = doctor.check_intent_end("1")
    result = find(checks, "intent_savepoint_truthful")
    assert_equal "pass", result[:status]
  end

  def test_the_torn_line_finding_carries_its_own_fix_hint
    write_savepoint(
      "2026-07-01T00:00:00Z  What  1--demo.md\n" \
      "2026-09-08T12:00:00Z  n1  running holder=auto-ce5\n"
    )
    checks = doctor.check_intent_end("1")
    result = find(checks, "intent_savepoint_truthful")
    assert result[:fixable]
    assert_match(/rebuild/i, result[:fix_hint])
    assert_match(/does not repair|cannot repair|preserves.*verbatim/i, result[:fix_hint])
  end

  # --- 4.14-4.15: spawn-preamble / agent-report survive a graph ledger (pins) -----

  def test_spawn_preamble_survives_a_graph_ledger
    write_full_lifecycle
    write_savepoint(
      "2026-07-01T00:00:00Z  What  1--demo.md\n" \
      "2026-07-01T00:01:00Z  How  checklist.md created\n" +
      transition_line(subject: "n1", state: "planned")
    )
    script = File.join(REPO, "scripts", "spawn-preamble")
    out = IO.popen(["ruby", script, @dir], &:read)
    assert $?.success?, "spawn-preamble must not crash on a ledger carrying node lines: #{out}"
    refute_empty out.strip
  end

  def test_agent_report_survives_a_graph_ledger
    write_full_lifecycle
    write_savepoint(
      "2026-07-01T00:00:00Z  What  1--demo.md\n" \
      "2026-07-01T00:01:00Z  How  checklist.md created\n" +
      transition_line(subject: "n1", state: "planned")
    )
    script = File.join(REPO, "scripts", "agent-report")
    out = IO.popen(["ruby", script, @dir], &:read)
    assert $?.success?, "agent-report must not crash on a ledger carrying node lines: #{out}"
    refute_empty out.strip
  end

  # --- 4.16: boarding tables (doc assertion) ---------------------------------------

  def test_the_boarding_tables_carry_a_transition_line_row
    auto_skill = File.read(File.join(REPO, "skills", "auto", "SKILL.md"))
    boarding_matrix = File.read(File.join(REPO, "skills", "intent-continuing", "references", "boarding-matrix.md"))

    [auto_skill, boarding_matrix].each do |text|
      assert_match(/transition/i, text, "boarding table must name a row for a ledger ending in a transition line")
    end
  end

  # --- S5, matrix rows 5.1-5.9: RoadmapSavepoint shares the appender -----------------

  def roadmap_home
    @roadmap_home ||= Dir.mktmpdir("roadmap-savepoint-guard")
  end

  def roadmap_path
    File.join(roadmap_home, "roadmaps", "demo.md")
  end

  def write_roadmap
    FileUtils.mkdir_p(File.dirname(roadmap_path))
    File.write(roadmap_path, "# Demo roadmap\n\n## Batches\n\n## Log\n")
  end

  def test_append_returns_true_on_write_and_false_on_dedup
    write_roadmap
    assert_equal true, RoadmapSavepoint.append(roadmap_path, "created", "first")
    assert_equal false, RoadmapSavepoint.append(roadmap_path, "created", "first")
  end

  def test_append_creates_the_ledger_and_its_directory
    write_roadmap
    ledger = RoadmapSavepoint.ledger_path_for(roadmap_path)
    refute File.exist?(ledger)
    RoadmapSavepoint.append(roadmap_path, "created", "first")
    assert File.exist?(ledger)
  end

  def test_an_unknown_event_still_raises_argumenterror
    write_roadmap
    assert_raises(ArgumentError) { RoadmapSavepoint.append(roadmap_path, "not-a-real-event", "x") }
  end

  def test_append_goes_through_the_guard
    write_roadmap
    calls = []
    fake_guard = Object.new
    fake_guard.define_singleton_method(:call) do |path, **opts, &blk|
      calls << [path, opts]
      content = File.exist?(path) ? File.read(path) : ""
      line = blk.call(content)
      File.open(path, "a") { |io| io.write(line) } if line
      line ? :written : :refused
    end
    RoadmapSavepoint.append(roadmap_path, "created", "first", guard: fake_guard)
    assert_equal 1, calls.length
  end

  def test_append_still_writes_on_a_filesystem_without_flock
    write_roadmap
    flock = ->(_handle, _mode) { raise Errno::ENOTSUP, "flock not supported" }
    wrote = RoadmapSavepoint.append(roadmap_path, "created", "first", flock: flock)
    assert_equal true, wrote
    assert_match(/created  first/, File.read(RoadmapSavepoint.ledger_path_for(roadmap_path)))
  end

  def test_a_contended_guard_propagates_unavailable
    write_roadmap
    flock = ->(_handle, _mode) { raise Errno::EWOULDBLOCK }
    sleeper = ->(_seconds) { nil }
    assert_raises(GuardedAppend::Unavailable) do
      RoadmapSavepoint.append(roadmap_path, "created", "first", flock: flock, sleeper: sleeper)
    end
  end

  def test_roadmap_savepoint_cli_exits_4_on_an_unavailable_guard
    write_roadmap
    cli = File.join(REPO, "scripts", "roadmap-savepoint")
    ledger = RoadmapSavepoint.ledger_path_for(roadmap_path)
    FileUtils.mkdir_p(File.dirname(ledger))
    File.write(ledger, "")
    handle = File.open(ledger, File::RDWR)
    handle.flock(File::LOCK_EX)
    begin
      out, err, status = Open3.capture3(RbConfig.ruby, cli, "append", "--roadmap", roadmap_path,
                                         "--event", "created", "--detail", "first")
      assert_equal 4, status.exitstatus, out + err
    ensure
      handle.flock(File::LOCK_UN)
      handle.close
    end
  end

  def test_roadmap_savepoint_does_not_reference_nodeledger
    text = File.read(File.join(REPO, "scripts", "lib", "roadmap_savepoint.rb"))
    refute_match(/NodeLedger/, text)
  end

  def test_rebuild_is_unchanged
    write_roadmap
    File.write(roadmap_path, <<~MD)
      # Demo roadmap

      ## Batches
      - [x] 1 demo — delivered

      ## Log
      - 2026-09-01 10:00 UTC created the roadmap
      - 2026-09-01 11:00 UTC dispatched 1
    MD
    count = RoadmapSavepoint.rebuild(roadmap_path)
    assert_operator count, :>, 0
  end
end
