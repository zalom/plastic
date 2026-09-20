# encoding: UTF-8
# frozen_string_literal: true

require_relative "../test_helper"
require "fileutils"
require "open3"
require "tmpdir"

class CliLauncherTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  LAUNCHER = File.join(ROOT, "bin", "plastic")

  def test_the_launcher_exists
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
    out, _err, status = Open3.capture3(LAUNCHER, "help")

    assert_predicate status, :success?
    assert_includes out, "plastic <command> [options]"
  end

  def test_running_the_launcher_through_a_symlink_works
    Dir.mktmpdir("plastic-launcher") do |dir|
      link = File.join(dir, "plastic")
      File.symlink(LAUNCHER, link)
      out, _err, status = Open3.capture3(link, "help")

      assert_predicate status, :success?
      assert_includes out, "plastic <command> [options]"
    end
  end

  def test_an_unknown_command_exits_with_the_usage_code
    _out, _err, status = Open3.capture3(LAUNCHER, "stauts")

    assert_equal 2, status.exitstatus
  end

  def test_the_launcher_starts_without_rubygems
    out, _err, status = Open3.capture3(LAUNCHER, "help")

    assert_predicate status, :success?
    refute_includes out, "rubygems"
  end

  def test_the_launcher_loads_only_the_command_it_runs
    script = "require #{File.join(ROOT, "scripts", "lib", "cli").inspect}\n" \
             "Plastic::CLI.new(['version'], out: StringIO.new, err: StringIO.new).run\n" \
             "puts $LOADED_FEATURES.grep(%r{/cli/commands/}).map { |f| File.basename(f) }.sort.join(',')\n"
    out, err, status = Open3.capture3("ruby", "--disable-gems", "-rstringio", "-e", script)

    assert_predicate status, :success?, err
    assert_equal "version.rb", out.strip
  end
end
