# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/child_process"
require "json"

class ChildProcessTest < Minitest::Test
  RUBY = RbConfig.ruby
  HELPER = File.expand_path("support/child_process.rb", __dir__)
  MACOS_ADDS = "__CF_USER_TEXT_ENCODING"
  REPORT = "print JSON.generate(ENV.to_h.merge('encoding' => Encoding.default_external.name))"

  def report(env = {}) = JSON.parse(ChildProcess.capture2(env, RUBY, "-rjson", "-e", REPORT).first).except(MACOS_ADDS)

  def test_a_child_sees_only_the_values_the_test_passes_and_the_fixed_ones
    seen = report("PLASTIC_HOME" => "/p", "HOME" => "/h")

    assert_equal({ "HOME" => "/h", "LANG" => "C.UTF-8", "PATH" => ChildProcess::PATH, "PLASTIC_HOME" => "/p", "encoding" => "UTF-8" }, seen)
  end

  def test_a_variable_of_the_running_session_never_reaches_a_child
    grandchild = "require #{HELPER.dump}; print ChildProcess.capture2(#{RUBY.dump}, '-e', 'p ENV[%q(CLAUDE_CODE_SESSION_ID)]').first"
    out, = ChildProcess.capture2({ "CLAUDE_CODE_SESSION_ID" => "c-1" }, RUBY, "-e", grandchild)

    assert_equal "nil\n", out
  end

  def test_a_child_with_no_home_gets_an_empty_one_that_is_removed
    out, = ChildProcess.capture2(RUBY, "-e", "print ENV['HOME'], ' ', Dir.children(ENV['HOME']).size")
    home, count = out.split

    assert_equal [true, "0"], [home.start_with?(Dir.tmpdir), count]
    refute_path_exists home
  end

  def test_a_nil_value_leaves_the_variable_unset
    refute report("LANG" => nil).key?("LANG")
  end

  def test_a_path_the_test_passes_replaces_the_fixed_one
    assert_equal "/nowhere", report("PATH" => "/nowhere").fetch("PATH")
  end

  def test_system_answers_with_the_exit_of_the_child
    assert_equal [true, false], [ChildProcess.system(RUBY, "-e", "exit 0"), ChildProcess.system(RUBY, "-e", "exit 3")]
  end
end
