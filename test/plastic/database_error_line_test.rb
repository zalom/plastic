# frozen_string_literal: true

require "sqlite3"
require_relative "../test_helper"

# A command that meets a local.db held by another process prints the plain line, never the name of the error class.
class DatabaseErrorLineTest < Plastic::TestCase
  fixtures :alpha_synced

  HELD = "local.db is held by another process; run the command again when it is free"

  def setup
    super
    @rival = SQLite3::Database.new(File.join(@plastic_home, "local.db"))
    @rival.execute_batch(Plastic::Graph::Schema.fetch(:local))
    @rival.execute("ALTER TABLE locks RENAME COLUMN locked_at TO taken_at") if older_column?
    @rival.execute("BEGIN IMMEDIATE")
  end

  def teardown
    @rival.close
    super
  end

  def older_column? = @rival.execute("PRAGMA table_info(locks)").any? { |column| column[1] == "locked_at" }

  def run_held(*words) = plastic(*words, input: '{"session_id":"s-1"}', env: { "PLASTIC_SESSION" => "s-1" }, table: Plastic::CLI::TABLE)

  def test_intent_lock_status_names_the_held_file_with_no_class_name
    call = run_held("intent", "lock", "status", "1")

    assert_equal [1, "", "plastic: #{HELD}\n"], [call.code, call.out, call.err]
  end

  def test_next_names_the_held_file_with_no_class_name
    call = run_held("next")

    assert_equal [1, "", "plastic: #{HELD}\n"], [call.code, call.out, call.err]
  end

  def test_hook_stop_names_the_held_file_with_no_class_name_and_exits_0
    call = run_held("hook", "stop")

    assert_equal [0, "", "plastic hook: #{HELD}\n"], [call.code, call.out, call.err]
  end
end
