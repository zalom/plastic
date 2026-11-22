# frozen_string_literal: true

require_relative "../../test_helper"

class HookTest < Plastic::TestCase
  def test_a_hook_prints_its_reply_as_plain_text
    call = plastic("hook", "echo", input: %({"session_id": "s-1"}))

    assert_equal [0, "session s-1\n"], [call.code, call.out]
    assert_equal "", call.err
  end

  def test_a_hook_with_no_input_reads_an_empty_event
    call = plastic("hook", "echo", input: "  ")

    assert_equal [0, "session \n", ""], [call.code, call.out, call.err]
  end

  def test_a_hook_with_no_reply_prints_nothing
    call = plastic("hook", "quiet")

    assert_equal [0, "", ""], [call.code, call.out, call.err]
  end

  def test_a_broken_event_reads_as_empty_with_one_stderr_line
    call = plastic("hook", "echo", input: "{not json")

    assert_equal [0, "session \n", "plastic hook: the event is not a JSON object; read as empty\n"], [call.code, call.out, call.err]
  end

  def test_a_hook_must_define_respond
    err = StringIO.new
    code = Plastic::CLI::Hook.call([], words: "hook", environment: environment(err:))

    assert_equal 0, code
    assert_equal "plastic hook: NoMethodError: Plastic::CLI::Hook must define respond\n", err.string
  end
end

# With backup.daily on, a hook does its own work first and takes the daily
# backup after it, so the backup holds what the hook wrote.
class HookDailyBackupOrderTest < Plastic::TestCase
  include BackupHomes
  include BackupTriggers
  include ConfigHomes

  MORNING = Time.new(2026, 1, 2, 9, 0, 0, "+01:00")

  def claimed_home
    home = fresh_home.tap { |path| seed_config(path, "global:\n  backup:\n    daily: true\n") }
    work = Plastic::Graph.open(home:, store: "alpha").work
    work.activate_intent("1")
    work.claim_node(intent_id: "1", id: work.add_node(intent_id: "1", title: "Claimed", criterion: "it works").id, by: "s-1")
    home
  end

  def test_the_start_of_day_backup_holds_the_claim_the_stop_hook_renewed
    home = claimed_home
    event = JSON.generate(session_id: "s-1", cwd: project_path(home, "alpha"))
    plastic("hook", "stop", env: env_for(home).merge("PLASTIC_SESSION" => "s-1"), input: event, table: Plastic::CLI::TABLE, clock: Clock.new(MORNING))
    copy = File.join(backups_dir(home), stamp(MORNING), "work_graph-#{stamp(MORNING)}.db")

    assert_equal [["2026-01-02T08:00:00Z"]], SQLite3::Database.new(copy).execute("SELECT seen_at FROM nodes WHERE claimed_by = ?", ["s-1"])
  end
end
