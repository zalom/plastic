# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require_relative "../../varar/support/kernel_command"
require_relative "../../../scripts/lib/plastic/hooks/entries"

# Hooks on a broken store: the harness never sees a crash. Each test builds
# its own Dir.mktmpdir home, never the shared template other tests reuse, so
# a corrupt database here cannot poison another test (review A20).
class BrokenStoreTest < Minitest::Test
  def test_hook_resume_on_an_unopenable_home_exits_zero_with_one_stderr_line
    Dir.mktmpdir do |home|
      File.write(File.join(home, ".plastic"), "not a directory")
      call = KernelCommand.new(home).run("hook", "resume", input: JSON.generate(source: "startup"),
        env: { "PLASTIC_SESSION" => "s-1" })

      assert_equal 0, call.code
      assert_equal "", call.out
      assert_equal 1, call.err.lines.size
    end
  end

  def test_hook_record_on_an_unopenable_home_exits_zero_with_one_stderr_line
    Dir.mktmpdir do |home|
      File.write(File.join(home, ".plastic"), "not a directory")
      call = KernelCommand.new(home).run("hook", "record", input: "{}", env: { "PLASTIC_SESSION" => "s-1" })

      assert_equal 0, call.code
      assert_equal "", call.out
      assert_equal 1, call.err.lines.size
    end
  end

  def test_hook_resume_on_a_corrupt_database_exits_zero
    Dir.mktmpdir do |home|
      kernel = KernelCommand.new(home)
      kernel.run!("intent", "new", "Alpha")
      File.binwrite(File.join(kernel.plastic_home, "local.db"), "not a sqlite file")

      call = kernel.run("hook", "resume", input: JSON.generate(source: "startup"), env: { "PLASTIC_SESSION" => "s-1" })

      assert_equal 0, call.code
      assert_equal "", call.out
      assert_equal "plastic hook: Plastic::Graph::Database::Error: local.db: file is not a database\n", call.err
    end
  end

  def test_hook_resume_with_an_empty_event_body_exits_zero
    Dir.mktmpdir do |home|
      call = KernelCommand.new(home).run("hook", "resume", input: "", env: {})

      assert_equal 0, call.code
      assert_match(/\APlastic: a new session in store global\. Run plastic next before anything else\.\n/, call.out)
      assert_equal "plastic hook: the event names no session; nothing recorded\n", call.err
    end
  end

  def failing_command(home)
    File.join(home, "plastic").tap do |path|
      File.write(path, "#!/bin/sh\nexit 2\n")
      File.chmod(0o755, path)
    end
  end

  def written_hook_lines(command)
    hooks = Plastic::Hooks::Entries.new(command: command, config: nil, launchers: {}).codex({})["hooks"]
    hooks.values.flatten.flat_map { |group| group["hooks"].map { |hook| hook["command"] } }
  end

  def test_every_hook_line_the_installer_writes_exits_zero_when_the_call_fails
    Dir.mktmpdir do |home|
      lines = written_hook_lines(failing_command(home))

      assert_equal Plastic::Hooks::Entries::EVENTS.size, lines.size
      lines.each do |line|
        assert system(line, chdir: home), "#{line} did not exit zero"
      end
    end
  end
end
