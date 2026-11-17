# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "package_fixture"
require "plastic/installations/package"
require "plastic/installations/codex_hooks"

class CodexHooksTest < Plastic::TestCase
  include PackageFixture

  def hooks_path = File.join(@home, ".codex", "hooks.json")

  def merge
    FileUtils.mkdir_p(File.dirname(hooks_path))
    changed = nil
    out, = capture_io { changed = Plastic::Installations::CodexHooks.new(Plastic::Installations::Package.new(REAL_PACKAGE, @plastic_home, "2.0.3", Plastic::Wiring.settings(@plastic_home))).merge(hooks_path) }
    [changed, out]
  end

  def stop_commands = JSON.parse(File.read(hooks_path)).dig("hooks", "Stop").flat_map { |group| group["hooks"].map { |hook| hook["command"] } }

  def test_the_install_names_the_hooks_it_changed
    changed, = merge

    assert_equal ["hook end", "hook start", "hook stop"], changed.sort
  end

  def test_a_second_install_changes_no_hook
    merge
    changed, = merge

    assert_empty changed
  end

  def test_an_entry_of_the_retired_dispatcher_is_purged_and_named_and_the_hook_of_the_person_stays
    write(hooks_path, JSON.generate("hooks" => { "Stop" => [{ "hooks" => [{ "type" => "command", "command" => "/x/codex-hook stop" }] }, { "hooks" => [{ "type" => "command", "command" => "mine" }] }] }))
    _, out = merge

    assert_includes out, "from hooks.json"
    assert_includes stop_commands, "mine"
    refute_includes stop_commands, "/x/codex-hook stop"
  end
end
