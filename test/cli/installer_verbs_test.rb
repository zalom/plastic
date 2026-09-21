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
    Plastic::CLI::Commands.const_get(const).call(argv, out: @out, err: @err, env: {},
      home: "/nowhere", runner: runner)
  end

  def each_verb_class
    VERBS.each_key do |verb|
      file, const, = Plastic::CLI::TABLE.fetch(verb)
      require File.expand_path("../../scripts/lib/cli/#{file}", __dir__)
      yield Plastic::CLI::Commands.const_get(const)
    end
  end

  def test_every_verb_runs_its_own_script
    VERBS.each do |verb, script|
      @calls = []
      command(verb)

      assert_equal [File.expand_path("../../scripts/#{script}", __dir__)], @calls.map(&:first)
    end
  end

  def test_every_script_the_table_names_is_on_disk
    VERBS.each_value do |script|
      assert_path_exists File.expand_path("../../scripts/#{script}", __dir__)
    end
  end

  def test_the_flags_reach_the_script_unchanged
    command("install", "--claude", "--advisor", "primary")

    assert_equal [["--claude", "--advisor", "primary"]], @calls.map(&:last)
  end

  def test_a_flag_the_script_does_not_know_exits_two
    assert_equal 2, command("uninstall", "--dry-run")
  end

  def test_a_flag_the_script_does_not_know_never_runs_the_script
    command("uninstall", "--dry-run")

    assert_empty @calls
  end

  def test_a_flag_the_script_does_not_know_is_named_on_the_error_stream
    command("uninstall", "--dry-run")

    assert_includes @err.string, "--dry-run is not a flag of this command"
  end

  def test_every_listed_flag_is_in_the_usage_line
    each_verb_class do |verb_class|
      verb_class::FLAGS.each { |flag| assert_includes verb_class::USAGE_LINE, flag }
    end
  end

  def test_every_listed_flag_is_read_by_the_script_or_the_installer_core
    core = File.read(File.expand_path("../../scripts/lib/installer_core.rb", __dir__))
    each_verb_class do |verb_class|
      source = File.read(File.expand_path("../../scripts/#{verb_class::SCRIPT}", __dir__)) + core

      verb_class::FLAGS.each { |flag| assert_includes source, %("#{flag}") }
    end
  end

  def test_a_rollback_with_no_target_claims_no_switch
    command("rollback")

    assert_includes @out.string, "because: the version says which build is installed"
  end

  def test_a_clean_install_exits_zero
    assert_equal 0, command("install")
  end

  def test_a_clean_install_names_the_verify_step
    command("install")

    assert_includes @out.string, "next: plastic version"
  end

  def test_a_clean_update_names_the_verify_step
    command("update")

    assert_includes @out.string, "next: plastic version"
  end

  def test_a_clean_uninstall_names_no_further_command
    command("uninstall")

    assert_includes @out.string, "next: none"
    assert_includes @out.string, "because: Plastic is removed from this machine's agents"
  end

  def test_a_failing_script_exits_one
    assert_equal 1, command("install", status: 7)
  end

  def test_a_failing_script_names_the_script_and_its_status
    command("install", status: 7)

    assert_includes @err.string, "install.rb exited 7"
  end

  def test_a_script_that_refuses_exits_three
    assert_equal 3, command("rollback", status: 3)
  end

  def test_a_failing_script_prints_no_next_step
    command("install", status: 7)

    refute_includes @out.string, "next:"
  end
end
