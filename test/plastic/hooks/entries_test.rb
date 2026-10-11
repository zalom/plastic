# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../../../scripts/lib/plastic/hooks/entries"
require_relative "../../../scripts/lib/plastic/config"

class EntriesTest < Minitest::Test
  COMMAND = "/opt/plastic/bin/plastic"
  LAUNCHERS = { statusline: "/opt/plastic/bin/statusline", screens: "/opt/plastic/bin/screens" }.freeze

  def config(text = "")
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "config.yml"), text)
      yield Plastic::Config.new(dir)
    end
  end

  def entries(text = "") = config(text) { |cfg| yield Plastic::Hooks::Entries.new(command: COMMAND, config: cfg, launchers: LAUNCHERS) }

  def commands_for(hooks, event) = Array(hooks[event]).flat_map { |group| group["hooks"].map { |hook| hook["command"] } }

  def test_claude_writes_one_group_per_event_with_no_harness_option
    entries { |rewriter| @settings = rewriter.claude({}) }

    assert_equal [%(env -u RUBYOPT "#{COMMAND}" hook start || true)], commands_for(@settings["hooks"], "SessionStart")
    assert_equal [%(env -u RUBYOPT "#{COMMAND}" hook stop || true)], commands_for(@settings["hooks"], "Stop")
    assert_equal [%(env -u RUBYOPT "#{COMMAND}" hook end || true)], commands_for(@settings["hooks"], "SessionEnd")
  end

  def test_owns_its_hook_commands_and_no_one_elses
    entries do |rewriter|
      @owned = [%(env -u RUBYOPT "#{COMMAND}" hook resume --harness codex || true), "/usr/local/bin/my-hook", "/opt/plastic/bin/plastic-ish"]
        .map { |command| rewriter.own?(command) }
    end

    assert_equal [true, false, false], @owned
  end

  def test_codex_writes_the_three_events_and_no_status_line
    entries { |rewriter| @hooks_json = rewriter.codex({ "hooks" => {} }) }

    assert_equal [%(env -u RUBYOPT "#{COMMAND}" hook start || true)], commands_for(@hooks_json["hooks"], "SessionStart")
    assert_nil @hooks_json["statusLine"]
  end

  def test_a_former_hook_command_with_the_harness_option_is_replaced
    former = { "matcher" => "", "hooks" => [{ "type" => "command", "command" => %(env -u RUBYOPT "#{COMMAND}" hook resume --harness claude-code || true) }] }

    entries do |rewriter|
      assert_equal [%(env -u RUBYOPT "#{COMMAND}" hook start || true)], commands_for(rewriter.claude({ "hooks" => { "SessionStart" => [former] } })["hooks"], "SessionStart")
    end
  end

  def test_a_rerun_gives_one_group_per_event_not_two
    entries do |rewriter|
      once = rewriter.claude({})
      twice = rewriter.claude(once)

      assert_equal 1, Array(twice["hooks"]["SessionStart"]).size
    end
  end

  def test_statusline_true_writes_the_launcher
    entries("statusline: true\n") { |rewriter| assert_equal LAUNCHERS[:statusline], rewriter.claude({})["statusLine"]["command"] }
  end

  def test_statusline_false_removes_only_our_own_status_line
    entries("statusline: false\n") do |rewriter|
      ours = rewriter.claude({})

      refute_includes ours, "statusLine"

      foreign = rewriter.claude({ "statusLine" => { "type" => "command", "command" => "/other/status" } })

      assert_equal "/other/status", foreign["statusLine"]["command"]
    end
  end

  def test_screens_true_writes_a_message_display_group
    entries("screens: true\n") do |rewriter|
      settings = rewriter.claude({})
      command = commands_for(settings["hooks"], "MessageDisplay").first

      assert_equal %(env -u RUBYOPT "#{LAUNCHERS[:screens]}" || true), command
    end
  end

  def test_screens_false_removes_ours_and_keeps_a_users_message_display_hook
    entries("screens: false\n") do |rewriter|
      foreign = { "matcher" => "", "hooks" => [{ "type" => "command", "command" => "/user/own-display" }] }
      settings = rewriter.claude({ "hooks" => { "MessageDisplay" => [foreign] } })

      assert_equal [foreign], settings["hooks"]["MessageDisplay"]
    end
  end

  def test_statusline_false_removes_our_own_status_line_when_present
    ours = { "statusLine" => { "type" => "command", "command" => LAUNCHERS[:statusline] } }

    entries("statusline: false\n") { |rewriter| refute_includes rewriter.claude(ours), "statusLine" }
  end

  def test_statusline_true_keeps_a_status_line_the_user_set
    foreign = { "statusLine" => { "type" => "command", "command" => "/other/status" } }

    entries("statusline: true\n") { |rewriter| assert_equal "/other/status", rewriter.claude(foreign)["statusLine"]["command"] }
  end

  def test_screens_true_keeps_a_users_message_display_hook_beside_ours
    foreign = { "matcher" => "", "hooks" => [{ "type" => "command", "command" => "/user/own-display" }] }

    entries("screens: true\n") do |rewriter|
      commands = commands_for(rewriter.claude({ "hooks" => { "MessageDisplay" => [foreign] } })["hooks"], "MessageDisplay")

      assert_equal ["/user/own-display", %(env -u RUBYOPT "#{LAUNCHERS[:screens]}" || true)], commands
    end
  end

  def test_an_old_launcher_is_matched_by_its_file_name_not_a_substring
    old = { "matcher" => "", "hooks" => [{ "type" => "command", "command" => '"/u/.claude/hooks/plastic-session-start"' }] }
    user = { "matcher" => "", "hooks" => [{ "type" => "command", "command" => "/u/.claude/hooks/plastic-writing-style" }] }

    entries do |rewriter|
      commands = commands_for(rewriter.claude({ "hooks" => { "SessionStart" => [old, user] } })["hooks"], "SessionStart")

      assert_equal ["/u/.claude/hooks/plastic-writing-style", %(env -u RUBYOPT "#{COMMAND}" hook start || true)], commands
    end
  end

  def test_an_old_installs_entries_are_removed_and_a_plain_user_hook_stays
    old_group = { "matcher" => "", "hooks" => [{ "type" => "command", "command" => "plastic-continue" }] }
    user_group = { "matcher" => "", "hooks" => [{ "type" => "command", "command" => "my-own-hook" }] }
    entries do |rewriter|
      settings = rewriter.claude({ "hooks" => { "SessionStart" => [old_group, user_group] } })
      commands = commands_for(settings["hooks"], "SessionStart")

      refute_includes commands, "plastic-continue"
      assert_includes commands, "my-own-hook"
    end
  end

  def test_no_launcher_writes_no_status_line_or_screens
    config do |cfg|
      settings = Plastic::Hooks::Entries.new(command: COMMAND, config: cfg, launchers: {}).claude({})

      refute_includes settings, "statusLine"
      refute_includes settings["hooks"], "MessageDisplay"
    end
  end
end
