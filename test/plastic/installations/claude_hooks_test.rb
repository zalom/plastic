# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "package_fixture"
require "plastic/installations/package"
require "plastic/installations/claude_hooks"

class ClaudeHooksTest < Plastic::TestCase
  include PackageFixture
  include ConfigHomes

  def config_with(text) = seed_config(@plastic_home, text)

  def package(root = REAL_PACKAGE) = Plastic::Installations::Package.new(root, @plastic_home, "2.0.3", Plastic::Wiring.settings(@plastic_home))

  def settings_path = File.join(@home, ".claude", "settings.json")

  def merge(settings, times: 1, root: REAL_PACKAGE, choice: :plastic)
    write(settings_path, JSON.generate(settings))
    out = ""
    hooks = Plastic::Installations::ClaudeHooks.new(package(root), File.join(@home, ".claude"))
    times.times { out, = capture_io { (choice == :keep) ? hooks.merge_keeping_status_line(settings_path) : hooks.merge(settings_path) } }
    [JSON.parse(File.read(settings_path)), out]
  end

  def commands(settings, event) = Array(settings["hooks"][event]).flat_map { |group| Array(group.is_a?(Hash) ? group["hooks"] : nil).map { |hook| hook["command"] } }

  def test_registered_events_are_added_as_groups_with_their_launcher_command
    write(settings_path, "{}")
    registered = { "PreCompact" => [{ "matcher" => "", "hooks" => [{ "name" => "check-update", "status" => "Checking" }] }] * 2 }
    capture_io { Plastic::Installations::ClaudeHooks.new(package, File.join(@home, ".claude"), registered:).merge(settings_path) }

    assert_equal [File.join(@home, ".claude", "hooks", "plastic-check-update")] * 2, commands(JSON.parse(File.read(settings_path)), "PreCompact")
  end

  def test_the_install_writes_the_kernel_hooks
    settings, = merge({})
    kernel = %("#{File.join(@plastic_home, "exe", "plastic")}")
    expected = { "SessionStart" => "#{kernel} hook start", "Stop" => "#{kernel} hook stop", "SessionEnd" => "#{kernel} hook end" }

    assert_empty(expected.reject { |event, text| commands(settings, event).any? { |cmd| cmd.include?(text) } })
  end

  def test_the_retired_update_check_hook_is_removed_and_not_named_as_the_persons_own
    old = { "hooks" => { "SessionStart" => [{ "matcher" => "", "hooks" => [{ "type" => "command", "command" => "~/.claude/hooks/plastic-check-update" }] }] } }
    settings, out = merge(old)

    assert_equal [[], false, true, true], [commands(settings, "SessionStart").grep(/check-update/), out.include?("Kept"), out.ascii_only?, out.include?("plastic-check-update")]
  end

  def test_a_kept_hook_with_the_reserved_prefix_is_named_in_plain_ascii
    own = { "hooks" => { "Stop" => [{ "matcher" => "", "hooks" => [{ "type" => "command", "command" => "~/.claude/hooks/plastic-mine" }] }] } }
    _settings, out = merge(own)

    assert_includes out, "Kept 1 hook(s)"
    assert_predicate out, :ascii_only?
  end

  def test_the_install_registers_no_check_update
    settings, = merge({})

    assert_empty(commands(settings, "SessionStart").grep(/check-update/))
  end

  def test_a_release_install_binds_the_hooks_to_the_active_launcher
    share = File.join(@home, ".local", "share", "plastic")
    root = File.join(share, "releases", "2.0.3")
    former = %(env -u RUBYOPT "#{File.join(@plastic_home, "bin", "plastic")}" hook resume --harness claude-code || true)
    settings, = merge({ "hooks" => { "SessionStart" => [{ "matcher" => "", "hooks" => [{ "type" => "command", "command" => former }] }] } }, root:)

    assert_equal [%(env -u RUBYOPT "#{File.join(share, "active", "bin", "plastic")}" hook start || true)], commands(settings, "SessionStart").grep(/hook start/)
  end

  def test_a_release_install_over_a_repository_install_keeps_one_group_per_event
    merge({})
    share = File.join(@home, ".local", "share", "plastic")
    settings, = merge(JSON.parse(File.read(settings_path)), root: File.join(share, "releases", "2.0.3"))
    kernel = %w[SessionStart Stop SessionEnd].map { |event| commands(settings, event).grep(/plastic"? hook (start|stop|end)/) }

    assert_equal [[1, 1, 1], true], [kernel.map(&:size), kernel.flatten.all? { |cmd| cmd.include?("#{share}/active/bin/plastic") }]
  end

  def test_a_second_install_keeps_one_group_per_event
    settings, = merge({}, times: 2)

    assert_equal 1, commands(settings, "Stop").size
  end

  def test_a_hook_of_the_person_stays_and_a_stale_plastic_hook_is_removed_and_named
    mine = { "matcher" => "", "hooks" => [{ "type" => "command", "command" => "my-stop" }] }
    stale = { "matcher" => "", "hooks" => [{ "type" => "command", "command" => "#{@home}/.claude/hooks/plastic-session-start" }] }
    settings, out = merge({ "hooks" => { "Stop" => [mine], "SessionStart" => [stale] } })

    assert_includes commands(settings, "Stop"), "my-stop"
    assert_includes out, "  Removed 1 stale Plastic hook entry from settings.json:\n"
  end

  def test_two_stale_plastic_hooks_are_removed_and_counted_in_the_plural
    stale = ->(name) { { "matcher" => "", "hooks" => [{ "type" => "command", "command" => "#{@home}/.claude/hooks/plastic-#{name}" }] } }
    _, out = merge({ "hooks" => { "SessionStart" => [stale.call("session-start")], "Stop" => [stale.call("stop")] } })

    assert_includes out, "  Removed 2 stale Plastic hook entries from settings.json:\n"
  end

  def test_a_hook_of_the_person_with_the_reserved_prefix_stays_and_is_named
    reserved = { "matcher" => "", "hooks" => [{ "type" => "command", "command" => "~/.claude/hooks/plastic-mine" }] }
    settings, out = merge({ "hooks" => { "Stop" => [reserved, { "command" => "plastic-bare" }, "text"] } })

    assert_includes commands(settings, "Stop"), "~/.claude/hooks/plastic-mine"
    assert_includes out, "Kept 2 hook(s) Plastic does not own, named with the reserved plastic- prefix"
  end

  def test_the_status_line_of_the_person_is_kept_in_the_cache_and_replaced_when_plastic_is_chosen_and_on
    config_with("global:\n  statusline: true\n")
    settings, = merge({ "statusLine" => { "type" => "command", "command" => "mine" } })

    assert_equal "#{@home}/.claude/hooks/plastic-statusline", settings.dig("statusLine", "command")
    assert_equal "mine", JSON.parse(File.read(File.join(@plastic_home, ".cache", "original-statusline.json")))["command"]
  end

  def test_the_status_line_of_the_person_stays_when_they_chose_to_keep_it
    config_with("global:\n  statusline: true\n")
    settings, = merge({ "statusLine" => { "type" => "command", "command" => "mine" } }, choice: :keep)

    assert_equal "mine", settings.dig("statusLine", "command")
  end

  def test_a_status_line_stays_off_while_the_flag_is_off
    refute merge({}, choice: :plastic).first.key?("statusLine")
  end

  def test_a_settings_file_that_does_not_exist_is_started_from_nothing
    FileUtils.mkdir_p(File.dirname(settings_path))
    Plastic::Installations::ClaudeHooks.new(package, File.join(@home, ".claude")).merge(settings_path)

    assert_includes JSON.parse(File.read(settings_path)).keys, "hooks"
  end

  def test_the_status_line_that_is_plastics_own_is_not_kept_in_the_cache
    config_with("global:\n  statusline: true\n")
    merge({ "statusLine" => { "type" => "command", "command" => "#{@home}/.claude/hooks/plastic-statusline" } })

    refute_path_exists File.join(@plastic_home, ".cache", "original-statusline.json")
  end
end
