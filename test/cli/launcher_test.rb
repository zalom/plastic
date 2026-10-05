# frozen_string_literal: true

require_relative "../test_helper"
require "fileutils"
require "open3"
require "tmpdir"

class CliLauncherTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  LAUNCHER = File.join(ROOT, "bin", "plastic")

  # Every spawn below runs the real launcher, which resolves ~/.plastic and
  # ~/.claude from HOME. A throwaway HOME keeps a command that reads or writes
  # the store off the machine's own home directory, and PLASTIC_TMP does the
  # same for the session bridge files.
  def setup
    @home = Dir.mktmpdir("plastic-launcher-home")
    @tmp = Dir.mktmpdir("plastic-launcher-tmp")
    @env = {"HOME" => @home, "PLASTIC_TMP" => @tmp}
  end

  def teardown
    FileUtils.remove_entry(@home, true)
    FileUtils.remove_entry(@tmp, true)
  end

  def test_the_launcher_file_exists_in_bin
    assert_path_exists LAUNCHER
  end

  def test_the_launcher_is_executable
    assert File.executable?(LAUNCHER), "bin/plastic must be executable"
  end

  def test_the_shebang_turns_rubygems_off
    assert_equal "#!/usr/bin/env -S ruby --disable-gems", File.readlines(LAUNCHER).first.chomp
  end

  def test_the_launcher_is_short_enough_to_read_at_a_glance
    assert_operator File.readlines(LAUNCHER).length, :<=, 8
  end

  def test_running_the_launcher_prints_the_command_list
    out, err, status = Open3.capture3(@env, LAUNCHER, "help")

    assert_predicate status, :success?
    assert_includes out, "intent new"
    assert_equal "", err
  end

  def test_running_the_launcher_through_a_symlink_works
    Dir.mktmpdir("plastic-launcher") do |dir|
      link = File.join(dir, "plastic")
      File.symlink(LAUNCHER, link)
      out, err, status = Open3.capture3(@env, link, "help")

      assert_predicate status, :success?
      assert_includes out, "intent new"
      assert_equal "", err
    end
  end

  def test_an_unknown_command_exits_with_the_usage_code
    out, err, status = Open3.capture3(@env, LAUNCHER, "stauts")

    assert_equal [2, "", "plastic stauts is not in this build yet; it lands with its stage\n"], [status.exitstatus, out, err]
  end

  def test_the_launcher_starts_without_rubygems
    out, err, status = Open3.capture3(@env, LAUNCHER, "help")

    assert_predicate status, :success?
    refute_includes out, "rubygems"
    assert_equal "", err
  end

  def test_the_launcher_leaves_the_home_it_runs_under_untouched
    Open3.capture3(@env, LAUNCHER, "help")

    assert_empty Dir.children(@home)
  end

  def test_the_launcher_loads_only_the_command_it_runs
    script = "require_relative #{File.join(ROOT, "scripts", "lib", "plastic").inspect}\n" \
             "name = Plastic::CLI.find(['intent', 'new'])\n" \
             "Plastic::CLI.tool(name)\n" \
             "puts $LOADED_FEATURES.grep(%r{/plastic/commands/}).map { |f| File.basename(f) }.sort.join(',')\n"
    out, err, status = Open3.capture3(@env, "ruby", "--disable-gems", "-e", script)

    assert_predicate status, :success?, err
    assert_equal "intent_new.rb", out.strip
  end
end
