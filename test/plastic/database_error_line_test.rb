# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "sqlite3"
require_relative "../varar/support/kernel_command"

# A command that meets a local.db held by another process prints the plain line, never the name of the error class.
# Each test builds its own throwaway home, so the shared test home never meets the rival connection.
class DatabaseErrorLineTest < Minitest::Test
  HELD = "local.db is held by another process; run the command again when it is free"

  def held_home
    Dir.mktmpdir do |home|
      kernel = KernelCommand.new(home)
      kernel.command!("intent", "new", "Alpha")
      rival = SQLite3::Database.new(File.join(kernel.plastic_home, "local.db"))
      rival.execute("ALTER TABLE locks RENAME COLUMN locked_at TO taken_at")
      rival.execute("BEGIN IMMEDIATE")
      begin
        yield kernel
      ensure
        rival.close
      end
    end
  end

  def test_intent_lock_status_names_the_held_file_with_no_class_name
    held_home do |kernel|
      call = kernel.command("intent", "lock", "status", "1")

      assert_equal [1, "", "plastic: #{HELD}\n"], [call.code, call.out, call.err]
    end
  end

  def test_next_names_the_held_file_with_no_class_name
    held_home do |kernel|
      call = kernel.command("next")

      assert_equal [1, "", "plastic: #{HELD}\n"], [call.code, call.out, call.err]
    end
  end

  def test_hook_stop_names_the_held_file_with_no_class_name_and_exits_0
    held_home do |kernel|
      call = kernel.command("hook", "stop", input: '{"session_id":"s-1"}', env: { "PLASTIC_SESSION" => "s-1" })

      assert_equal [0, "", "plastic hook: #{HELD}\n"], [call.code, call.out, call.err]
    end
  end
end
