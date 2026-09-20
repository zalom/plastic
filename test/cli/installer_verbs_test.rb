# encoding: UTF-8
# frozen_string_literal: true

require_relative "../test_helper"
require "stringio"
require_relative "../../scripts/lib/cli"

class CliInstallerVerbsTest < Minitest::Test
  VERBS = {"install" => "install.rb", "update" => "update.rb",
           "uninstall" => "uninstall.rb", "rollback" => "rollback.rb"}.freeze

  def setup
    @out = StringIO.new
    @err = StringIO.new
    @calls = []
  end

  def command(verb, *argv, status: 0)
    file, const, = Plastic::CLI::TABLE.fetch(verb)
    require File.expand_path("../../scripts/lib/cli/#{file}", __dir__)
    runner = lambda do |path, arguments|
      @calls << [path, arguments]
      status
    end
    Plastic::CLI::Commands.const_get(const).new(argv, out: @out, err: @err, env: {},
      home: "/nowhere", runner: runner)
  end

  def test_every_verb_runs_its_own_script
    VERBS.each do |verb, script|
      @calls = []
      command(verb).run

      assert_equal [File.expand_path("../../scripts/#{script}", __dir__)], @calls.map(&:first)
    end
  end

  def test_every_script_the_table_names_is_on_disk
    VERBS.each_value do |script|
      assert_path_exists File.expand_path("../../scripts/#{script}", __dir__)
    end
  end

  def test_the_flags_reach_the_script_unchanged
    command("install", "--claude", "--dry-run").run

    assert_equal [["--claude", "--dry-run"]], @calls.map(&:last)
  end

  def test_a_clean_install_exits_zero
    assert_equal 0, command("install").run
  end

  def test_a_clean_install_names_the_verify_step
    command("install").run

    assert_includes @out.string, "next: plastic version"
  end

  def test_a_clean_update_names_the_verify_step
    command("update").run

    assert_includes @out.string, "next: plastic version"
  end

  def test_a_clean_uninstall_names_no_further_command
    command("uninstall").run

    assert_includes @out.string, "next: none"
    assert_includes @out.string, "because: Plastic is removed from this machine's agents"
  end

  def test_a_failing_script_exits_one
    assert_equal 1, command("install", status: 7).run
  end

  def test_a_failing_script_names_the_script_and_its_status
    command("install", status: 7).run

    assert_includes @err.string, "install.rb exited 7"
  end

  def test_a_script_that_refuses_exits_three
    assert_equal 3, command("rollback", status: 3).run
  end

  def test_a_failing_script_prints_no_next_step
    command("install", status: 7).run

    refute_includes @out.string, "next:"
  end
end
