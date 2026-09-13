# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "time"

require_relative "../scripts/lib/node_ledger"
require_relative "../scripts/lib/arm"
require_relative "../scripts/lib/lock"
require_relative "../scripts/lib/installer_core"

# Intent 335 (G2), S3: node-transition, the command that refuses. Matrix rows
# 3.1-3.26 in actions/ACTION_1.md. Every test spawns the real CLI as a subprocess
# (Open3), the house pattern for scripts/append-ledger, scripts/end-intent, and
# scripts/maintenance-run.
class NodeTransitionTest < Minitest::Test
  NODE_TRANSITION = File.expand_path("../scripts/node-transition", __dir__)
  REPO = File.expand_path("..", __dir__)

  RUNNING_FIELDS = { holder: "auto-owner", expires: "2026-09-08T20:00:00Z", input: "abc123", model: "sonnet" }.freeze

  def setup
    @home = Dir.mktmpdir("node-transition")
    @intent_dir = build_intent_dir(@home)
    @savepoint_path = File.join(@intent_dir, "savepoint.md")
  end

  def teardown
    FileUtils.remove_entry(@home) if @home && Dir.exist?(@home)
  end

  # --- fixtures -----------------------------------------------------------------

  def build_intent_dir(home, id: "1", slug: "demo")
    dir = File.join(home, "store", "#{id}--#{slug}")
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "#{id}--#{slug}.md"),
               "---\nid: \"#{id}\"\nintent: \"t\"\n---\n\n## Intent\nbody\n")
    dir
  end

  def write_lock(dir, owner:, delegates: [])
    File.write(File.join(dir, "delivery.lock"),
               JSON.generate("type" => "delivery", "owner_session" => owner, "delegates" => delegates))
  end

  def append_line(dir, subject:, state:, fields: {}, comment: nil, now: Time.utc(2026, 9, 8, 18, 0, 0))
    line = NodeLedger.transition_line(subject: subject, state: state, fields: fields, comment: comment, now: now)
    File.open(File.join(dir, "savepoint.md"), "a") { |io| io.write(line) }
  end

  def append_raw(dir, line)
    line = "#{line}\n" unless line.end_with?("\n")
    File.open(File.join(dir, "savepoint.md"), "a") { |io| io.write(line) }
  end

  def running_field_args(fields = RUNNING_FIELDS)
    fields.flat_map { |k, v| ["--field", "#{k}=#{v}"] }
  end

  def run_cli(*args, env: {})
    full_env = { "CLAUDE_CODE_SESSION_ID" => nil }.merge(env)
    Open3.capture3(full_env, RbConfig.ruby, NODE_TRANSITION, *args)
  end

  def derived_key(intent_dir)
    Arm.derive_key(Arm.store_for(intent_dir), Arm.intent_id_for(intent_dir))
  end

  # --- 3.1-3.6: session resolution and lock ownership ---------------------------

  def test_running_without_the_lock_exits_4_and_writes_nothing
    out, err, status = run_cli(@intent_dir, "--node", "n1", "--state", "running", *running_field_args)
    assert_equal 4, status.exitstatus, out + err
    refute File.exist?(@savepoint_path)
  end

  def test_running_by_the_lock_owner_is_accepted
    write_lock(@intent_dir, owner: "sess-a")
    _out, err, status = run_cli(@intent_dir, "--node", "n1", "--state", "running", "--session", "sess-a",
                                 *running_field_args)
    assert_equal 0, status.exitstatus, err
    assert_match(/running/, File.read(@savepoint_path))
  end

  def test_an_unset_session_resolves_to_the_derived_auto_key
    write_lock(@intent_dir, owner: derived_key(@intent_dir))
    _out, err, status = run_cli(@intent_dir, "--node", "n1", "--state", "running", *running_field_args)
    assert_equal 0, status.exitstatus, err
  end

  def test_a_foreign_env_session_falls_back_to_the_derived_owner_key
    write_lock(@intent_dir, owner: derived_key(@intent_dir))
    _out, err, status = run_cli(@intent_dir, "--node", "n1", "--state", "running", *running_field_args,
                                 env: { "CLAUDE_CODE_SESSION_ID" => "foreign-session" })
    assert_equal 0, status.exitstatus, err
  end

  def test_an_explicit_non_owner_session_is_refused_without_fallback
    write_lock(@intent_dir, owner: derived_key(@intent_dir))
    out, err, status = run_cli(@intent_dir, "--node", "n1", "--state", "running", "--session", "not-the-owner",
                                *running_field_args)
    assert_equal 4, status.exitstatus, out + err
    refute File.exist?(@savepoint_path)
  end

  def test_a_registered_delegate_may_write_running
    write_lock(@intent_dir, owner: "owner-x")
    Lock.add_delegate(@intent_dir, delegate: "delegate-y", session: "owner-x")
    _out, err, status = run_cli(@intent_dir, "--node", "n1", "--state", "running", "--session", "delegate-y",
                                 *running_field_args)
    assert_equal 0, status.exitstatus, err
  end

  # --- 3.7-3.13: readiness ---------------------------------------------------------

  def test_running_with_an_unfinished_needs_target_exits_5
    write_lock(@intent_dir, owner: "sess-a")
    # n1 has no lines at all: defaults to "planned", not "done".
    out, err, status = run_cli(@intent_dir, "--node", "n2", "--state", "running", "--session", "sess-a",
                                "--needs", "n1", *running_field_args)
    assert_equal 5, status.exitstatus, out + err
  end

  def test_running_after_an_unattributed_done_exits_5
    write_lock(@intent_dir, owner: "sess-a")
    append_line(@intent_dir, subject: "n1", state: "done", fields: { gates: "suite", commit: "abc" }) # no holder=
    out, err, status = run_cli(@intent_dir, "--node", "n2", "--state", "running", "--session", "sess-a",
                                "--needs", "n1", *running_field_args)
    assert_equal 5, status.exitstatus, out + err
  end

  def test_running_after_a_torn_done_exits_5
    write_lock(@intent_dir, owner: "sess-a")
    append_raw(@intent_dir, "2026-09-08T18:00:00Z  n1  done commit=abc holder=auto-x") # torn: no gates=
    out, err, status = run_cli(@intent_dir, "--node", "n2", "--state", "running", "--session", "sess-a",
                                "--needs", "n1", *running_field_args)
    assert_equal 5, status.exitstatus, out + err
  end

  def test_running_on_an_already_running_subject_exits_5
    write_lock(@intent_dir, owner: "sess-a")
    append_line(@intent_dir, subject: "n1", state: "running", fields: RUNNING_FIELDS)
    out, err, status = run_cli(@intent_dir, "--node", "n1", "--state", "running", "--session", "sess-a",
                                *running_field_args)
    assert_equal 5, status.exitstatus, out + err
  end

  def test_running_after_failed_verification_is_accepted
    write_lock(@intent_dir, owner: "sess-a")
    append_line(@intent_dir, subject: "n1", state: "failed_verification", fields: { gates: "suite", reason: "flaky" })
    _out, err, status = run_cli(@intent_dir, "--node", "n1", "--state", "running", "--session", "sess-a",
                                 *running_field_args)
    assert_equal 0, status.exitstatus, err
  end

  def test_running_after_reclaimed_is_accepted
    write_lock(@intent_dir, owner: "sess-a")
    append_line(@intent_dir, subject: "n1", state: "reclaimed",
                fields: { holder: "auto-old", expired: "2026-09-08T18:30:00Z" })
    _out, err, status = run_cli(@intent_dir, "--node", "n1", "--state", "running", "--session", "sess-a",
                                 *running_field_args)
    assert_equal 0, status.exitstatus, err
  end

  def test_explicit_needs_wins_over_graph_md
    write_lock(@intent_dir, owner: "sess-a")
    File.write(File.join(@intent_dir, "graph.md"), <<~MD)
      ## Graph

      - n2 (work) needs: n5
    MD
    # n5 is never done, so graph.md's needs would refuse; an explicit empty
    # --needs must override it entirely.
    _out, err, status = run_cli(@intent_dir, "--node", "n2", "--state", "running", "--session", "sess-a",
                                 "--needs", "", *running_field_args)
    assert_equal 0, status.exitstatus, err
  end

  # --- 7.1 (post-execution review): the readiness decision must happen INSIDE the
  # guard's hold, or two concurrent writers both decide a node is ready and both append
  # running. Fork-based against real OS flock (modelled on GuardedAppendTest's
  # test_forked_writers_produce_one_line_each_with_no_interleaving), not sequential:
  # the reviewer reproduced 17/20 rounds landing more than one running line with four
  # concurrent writers.

  def test_concurrent_running_writers_produce_exactly_one_running_line
    script = NODE_TRANSITION
    rounds = 20
    writers = 4

    rounds.times do |round|
      home = Dir.mktmpdir("node-transition-race")
      begin
        intent_dir = build_intent_dir(home)
        write_lock(intent_dir, owner: "sess-a")
        savepoint_path = File.join(intent_dir, "savepoint.md")
        args = [intent_dir, "--node", "n1", "--state", "running", "--session", "sess-a"] + running_field_args

        pids = Array.new(writers) do
          fork do
            $PROGRAM_NAME = "node-transition-race-child"
            $stdout.reopen(File::NULL, "w")
            $stderr.reopen(File::NULL, "w")
            load script
            status = begin
              NodeTransition.main(args)
              0
            rescue SystemExit => e
              e.status
            end
            exit!(status)
          end
        end
        pids.each { |pid| Process.waitpid(pid) }

        running_lines = File.exist?(savepoint_path) ? File.readlines(savepoint_path).grep(/  running /) : []
        assert_equal 1, running_lines.length,
                     "round #{round}: expected exactly one running line, got #{running_lines.length}"
      ensure
        FileUtils.remove_entry(home)
      end
    end
  end

  # --- 3.14-3.15: done ---------------------------------------------------------------

  def test_done_without_gates_or_evidence_exits_2
    out, _err, status = run_cli(@intent_dir, "--node", "n1", "--state", "done")
    assert_equal 2, status.exitstatus, out
    refute File.exist?(@savepoint_path)
  end

  def test_done_does_not_require_the_lock
    refute File.exist?(File.join(@intent_dir, "delivery.lock"))
    _out, err, status = run_cli(@intent_dir, "--node", "n1", "--state", "done",
                                 "--field", "gates=suite", "--field", "commit=abc")
    assert_equal 0, status.exitstatus, err
  end

  # --- 3.16-3.19: reclaimed -----------------------------------------------------------

  def test_reclaimed_before_expiry_exits_6
    append_line(@intent_dir, subject: "n1", state: "running", fields: RUNNING_FIELDS)
    out, err, status = run_cli(@intent_dir, "--node", "n1", "--state", "reclaimed",
                                "--field", "holder=auto-owner", "--field", "expired=2026-09-08T19:00:00Z",
                                "--now", "2026-09-08T19:00:00Z")
    assert_equal 6, status.exitstatus, out + err
  end

  def test_reclaimed_after_expiry_is_accepted
    append_line(@intent_dir, subject: "n1", state: "running", fields: RUNNING_FIELDS)
    _out, err, status = run_cli(@intent_dir, "--node", "n1", "--state", "reclaimed",
                                 "--field", "holder=auto-owner", "--field", "expired=2026-09-08T20:01:00Z",
                                 "--now", "2026-09-08T20:05:00Z")
    assert_equal 0, status.exitstatus, err
  end

  def test_reclaimed_with_no_running_line_exits_6
    out, err, status = run_cli(@intent_dir, "--node", "n1", "--state", "reclaimed",
                                "--field", "holder=auto-owner", "--field", "expired=2026-09-08T20:01:00Z")
    assert_equal 6, status.exitstatus, out + err
  end

  def test_reclaimed_is_hand_writable_without_the_lock
    refute File.exist?(File.join(@intent_dir, "delivery.lock"))
    append_line(@intent_dir, subject: "n1", state: "running", fields: RUNNING_FIELDS)
    _out, err, status = run_cli(@intent_dir, "--node", "n1", "--state", "reclaimed",
                                 "--field", "holder=auto-owner", "--field", "expired=2026-09-08T20:01:00Z",
                                 "--now", "2026-09-08T20:05:00Z")
    assert_equal 0, status.exitstatus, err
    refute File.exist?(File.join(@intent_dir, "delivery.lock"))
  end

  # --- 7.4-7.5 (post-execution review): reclaim must check the CURRENT status, not
  # only the expiry of the last running line -----------------------------------------

  def test_reclaimed_on_a_done_subject_exits_6
    # The running line's own expires= must be genuinely in the past, so this test fails
    # for the status-check gap (blocker 2), never for the pre-existing expiry check.
    append_line(@intent_dir, subject: "n1", state: "running",
                fields: { holder: "h", expires: "2020-01-01T00:00:00Z", input: "p", model: "sonnet" },
                now: Time.utc(2019, 12, 31, 23, 0, 0))
    append_line(@intent_dir, subject: "n1", state: "done", fields: { gates: "suite", commit: "abc", holder: "h" },
                now: Time.utc(2020, 1, 1, 1, 0, 0))
    before = File.read(@savepoint_path)
    out, err, status = run_cli(@intent_dir, "--node", "n1", "--state", "reclaimed",
                                "--field", "holder=h", "--field", "expired=2020-01-02T00:00:00Z",
                                "--now", "2020-01-02T00:00:01Z")
    assert_equal 6, status.exitstatus, out + err
    assert_equal before, File.read(@savepoint_path), "a done node reclaimed as expired must not revert to planned"
  end

  def test_reclaimed_on_a_running_expired_subject_is_still_accepted
    append_line(@intent_dir, subject: "n1", state: "running", fields: RUNNING_FIELDS)
    _out, err, status = run_cli(@intent_dir, "--node", "n1", "--state", "reclaimed",
                                 "--field", "holder=auto-owner", "--field", "expired=2026-09-08T20:01:00Z",
                                 "--now", "2026-09-08T20:05:00Z")
    assert_equal 0, status.exitstatus, err
  end

  # --- 3.20-3.23: general refusal hygiene -----------------------------------------

  def test_every_refusal_leaves_the_ledger_byte_identical
    append_line(@intent_dir, subject: "n1", state: "planned")
    before = File.read(@savepoint_path)

    run_cli(@intent_dir, "--node", "n1", "--state", "running", *running_field_args) # no lock: exit 4
    assert_equal before, File.read(@savepoint_path)

    run_cli(@intent_dir, "--node", "n1", "--state", "reclaimed",
            "--field", "holder=x", "--field", "expired=2026-09-08T20:01:00Z") # no running line: exit 6
    assert_equal before, File.read(@savepoint_path)
  end

  def test_an_unavailable_guard_exits_3
    File.write(@savepoint_path, "")
    handle = File.open(@savepoint_path, File::RDWR)
    handle.flock(File::LOCK_EX)
    begin
      out, err, status = run_cli(@intent_dir, "--node", "n9", "--state", "done",
                                  "--field", "gates=suite", "--field", "commit=abc")
      assert_equal 3, status.exitstatus, out + err
    ensure
      handle.flock(File::LOCK_UN)
      handle.close
    end
  end

  def test_a_bad_subject_exits_2
    out, _err, status = run_cli(@intent_dir, "--node", "N1", "--state", "planned")
    assert_equal 2, status.exitstatus, out
    refute File.exist?(@savepoint_path)
  end

  def test_a_non_intent_directory_exits_2
    plain_dir = Dir.mktmpdir("not-an-intent", @home)
    out, _err, status = run_cli(plain_dir, "--node", "n1", "--state", "planned")
    assert_equal 2, status.exitstatus, out
    refute File.exist?(File.join(plain_dir, "savepoint.md"))
  end

  # 7.7 (post-execution review) - a field key the parser cannot read back must be
  # refused at usage time, not silently emitted as a pair that swallows every field
  # rendered after it.
  def test_a_field_key_the_parser_cannot_read_exits_2
    out, err, status = run_cli(@intent_dir, "--node", "n1", "--state", "planned", "--field", "Sha=1")
    assert_equal 2, status.exitstatus, out + err
    refute File.exist?(@savepoint_path)
  end

  # --- 3.24-3.26: report verb, plain output, packaging ----------------------------

  def test_report_prints_torn_and_unattributed_lines
    append_raw(@intent_dir, "2026-09-08T18:00:00Z  n1  running holder=auto-ce5") # torn
    append_line(@intent_dir, subject: "n2", state: "done", fields: { gates: "suite", commit: "abc" }) # unattributed
    out, err, status = run_cli("report", @intent_dir)
    assert_equal 0, status.exitstatus, err
    assert_match(/torn/, out)
    assert_match(/unattributed/, out)
  end

  def test_output_is_plain_text_with_no_escape_sequences
    write_lock(@intent_dir, owner: "sess-a")
    out, err, status = run_cli(@intent_dir, "--node", "n1", "--state", "running", "--session", "sess-a",
                                *running_field_args)
    assert_equal 0, status.exitstatus, err
    refute_match(/\e\[/, out + err)
  end

  def test_the_three_new_files_are_in_the_installer_manifest
    core = InstallerCore.new(package_root: REPO, plastic_home: Dir.mktmpdir("installer-home"), version: "1.0.0-test")
    %w[scripts/lib/guarded_append.rb scripts/lib/node_ledger.rb scripts/node-transition].each do |rel|
      assert core.core_files.key?(rel), "#{rel} missing from core_files (installed ~/.plastic would lack it)"
      assert_equal rel, core.core_files[rel]
    end
  end
end
