# encoding: UTF-8
# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../scripts/lib/cli/legacy"

class CliLegacyTest < Minitest::Test
  def legacy(status, recorder = [])
    runner = lambda do |path, arguments|
      recorder << [path, arguments]
      status
    end
    Plastic::CLI::Legacy.new(env: {}, runner: runner)
  end

  def test_the_script_path_sits_in_the_package
    path = Plastic::CLI::Legacy.new(env: {}).script_path("install.rb")

    assert_equal File.expand_path("../../scripts/install.rb", __dir__), path
  end

  def test_the_package_root_can_be_injected_through_the_environment
    legacy = Plastic::CLI::Legacy.new(env: { "PLASTIC_PACKAGE_ROOT" => "/opt/plastic" })

    assert_equal "/opt/plastic/scripts/install.rb", legacy.script_path("install.rb")
  end

  def test_a_clean_run_answers_zero
    assert_equal 0, legacy(0).run("install.rb")
  end

  def test_the_arguments_reach_the_script
    recorder = []
    legacy(0, recorder).run("install.rb", "--claude", "--dry-run")

    assert_equal [["--claude", "--dry-run"]], recorder.map(&:last)
  end

  def test_the_script_path_reaches_the_runner
    recorder = []
    legacy(0, recorder).run("update.rb")

    assert_equal [File.expand_path("../../scripts/update.rb", __dir__)], recorder.map(&:first)
  end

  def test_a_failing_run_answers_its_status
    assert_equal 7, legacy(7).run("install.rb")
  end

  def test_a_run_that_exits_three_raises_a_refusal
    error = assert_raises(Plastic::CLI::Command::Refusal) { legacy(3).run("uninstall.rb") }

    assert_includes error.message, "uninstall.rb"
  end

  def test_a_run_that_exits_two_answers_two_rather_than_refusing
    assert_equal 2, legacy(2).run("install.rb")
  end
end
