# frozen_string_literal: true

require "json"
require "stringio"
require_relative "release_helper"

class InstallerReleaseHomeSyncTest < Minitest::Test
  include ReleaseHelper

  def test_links_the_launcher_to_the_active_release
    sync.call

    assert_equal File.join(share, "active", "bin", "plastic"), File.readlink(launcher)
  end

  def test_relinks_a_launcher_that_points_into_the_share
    FileUtils.mkdir_p(File.dirname(launcher))
    File.symlink(File.join(share, "bin", "plastic"), launcher)
    sync.call

    assert_equal File.join(share, "active", "bin", "plastic"), File.readlink(launcher)
  end

  def test_leaves_a_launcher_the_user_wrote_alone
    FileUtils.mkdir_p(File.dirname(launcher))
    File.write(launcher, "#!/bin/sh\necho mine\n")
    out = StringIO.new
    sync(out: out).call

    assert_equal "#!/bin/sh\necho mine\n", File.read(launcher)
    assert_includes out.string, "#{launcher} is not Plastic's launcher; it stays as it is"
  end

  def test_leaves_a_launcher_link_to_another_program_alone
    FileUtils.mkdir_p(File.dirname(launcher))
    File.symlink("/usr/local/lib/node_modules/@zalom/plastic/bin/plastic", launcher)
    sync(out: StringIO.new).call

    assert_equal "/usr/local/lib/node_modules/@zalom/plastic/bin/plastic", File.readlink(launcher)
  end

  def test_syncs_an_installed_home_through_the_active_release
    installed_home
    runs = []
    sync(run: ->(env, command) { runs << [env, command] }).call

    expected = { "PLASTIC_HOME" => plastic_home, "HOME" => user_home, "RUBYOPT" => nil, "BUNDLE_GEMFILE" => nil }

    assert_equal [[expected, [File.join(share, "active", "bin", "plastic"), "install", "--reinstall"]]], runs
  end

  def test_leaves_a_home_without_an_installation_unsynced
    runs = []
    sync(run: ->(env, command) { runs << [env, command] }).call

    assert_empty runs
    refute_path_exists plastic_home
  end

  def test_removes_the_hooks_of_both_launchers_and_keeps_the_users
    installed_home
    write_json(".claude/settings.json", "hooks" => hooks_with_ours, "statusLine" => { "command" => "/usr/local/bin/mine" })
    write_json(".codex/hooks.json", "hooks" => hooks_with_ours)
    sync.call

    expected = { "SessionStart" => [user_group] }

    assert_equal [expected, { "command" => "/usr/local/bin/mine" }], read_json(".claude/settings.json").values_at("hooks", "statusLine")
    assert_equal expected, read_json(".codex/hooks.json")["hooks"]
  end

  def test_leaves_a_settings_file_without_hooks_as_it_is
    installed_home
    write_json(".claude/settings.json", "statusLine" => { "command" => "/usr/local/bin/mine" })
    sync.call

    assert_equal({ "statusLine" => { "command" => "/usr/local/bin/mine" } }, read_json(".claude/settings.json"))
  end

  def test_names_the_managed_paths_and_never_the_stores
    home_with_stores
    managed = [*in_plastic_home("scripts", "config.yml"), File.join(user_home, ".claude", "settings.json"), check_update, launcher]

    assert_equal [managed, []], [managed & sync.paths, in_plastic_home("stores", "plastic.sqlite3") & sync.paths]
  end

  private

  def user_home = File.join(@root, "home")

  def plastic_home = File.join(user_home, ".plastic")

  def check_update = File.join(user_home, ".claude", "hooks", "plastic-check-update")

  def in_plastic_home(*names) = names.map { |name| File.join(plastic_home, name) }

  def share = File.join(user_home, ".local", "share", "plastic")

  def launcher = File.join(user_home, ".local", "bin", "plastic")

  def sync(run: ->(_env, _command) {}, out: StringIO.new)
    home = InstallerRelease::ManagedHome.new(plastic_home: plastic_home, user_home: user_home, launcher: launcher)
    InstallerRelease::HomeSync.new(share: share, home: home, run: run, out: out)
  end

  def home_with_stores
    installed_home
    FileUtils.mkdir_p([*in_plastic_home("scripts", "stores"), File.dirname(check_update)])
    write_json(".claude/settings.json", {})
    [*in_plastic_home("config.yml", "plastic.sqlite3"), check_update].each { |path| File.write(path, "") }
  end

  def installed_home
    FileUtils.mkdir_p(plastic_home)
    File.write(File.join(plastic_home, "VERSION"), "2.0.3\n")
  end

  def group(command) = { "matcher" => "", "hooks" => [{ "type" => "command", "command" => command }] }

  def user_group = group("/usr/local/bin/my-hook")

  def hooks_with_ours
    { "SessionStart" => [group(%(env -u RUBYOPT "#{File.join(share, "active", "bin", "plastic")}" hook resume || true)), user_group],
      "Stop" => [group(%(env -u RUBYOPT "#{File.join(plastic_home, "bin", "plastic")}" hook record || true))] }
  end

  def write_json(relative, data)
    path = File.join(user_home, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, JSON.generate(data))
  end

  def read_json(relative) = JSON.parse(File.read(File.join(user_home, relative)))
end
