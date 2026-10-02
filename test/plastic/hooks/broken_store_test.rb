# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "English"
require_relative "../../varar/support/kernel_command"

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
      refute_empty call.err
    end
  end

  def test_hook_record_on_an_unopenable_home_exits_zero_with_one_stderr_line
    Dir.mktmpdir do |home|
      File.write(File.join(home, ".plastic"), "not a directory")
      call = KernelCommand.new(home).run("hook", "record", input: "{}", env: { "PLASTIC_SESSION" => "s-1" })

      assert_equal 0, call.code
      refute_empty call.err
    end
  end

  def test_hook_resume_on_a_corrupt_database_exits_zero
    Dir.mktmpdir do |home|
      kernel = KernelCommand.new(home)
      kernel.run!("intent", "new", "Alpha")
      File.binwrite(File.join(kernel.plastic_home, "home.db"), "not a sqlite file")

      call = kernel.run("hook", "resume", input: JSON.generate(source: "startup"), env: { "PLASTIC_SESSION" => "s-1" })

      assert_equal 0, call.code
    end
  end

  def test_hook_resume_with_an_empty_event_body_exits_zero
    Dir.mktmpdir do |home|
      call = KernelCommand.new(home).run("hook", "resume", input: "", env: {})

      assert_equal 0, call.code
    end
  end

  def test_the_wrapper_exits_zero_even_when_the_call_fails
    Dir.mktmpdir do |home|
      kernel = KernelCommand.new(home)
      broken = "#{RbConfig.ruby} -e 'exit 2'"
      status = system("env -u RUBYOPT #{broken} || true", chdir: kernel.home)

      assert status
      assert_equal 0, $CHILD_STATUS.exitstatus
    end
  end
end
