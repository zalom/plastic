require "minitest/autorun"
require "tmpdir"
require "json"
require "fileutils"
require "stringio"

require_relative "../scripts/lib/installer_core"
require_relative "../scripts/lib/hook_registry"

PLASTIC_TEST_HOME_CODEX = File.join(Dir.tmpdir, "plastic-test-home-codex-#{Process.pid}")

# First-ever coverage of merge_codex_hooks/purge_stale_codex_hooks/remove_codex_hooks
# (intent 275). These paths had zero tests before this file: the Codex purge carried
# the same substring-ownership bug as the Claude side (cmd.include?("codex-hook")),
# just with no regression pin at all.
class MergeCodexHooksTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("codex-hooks-test")
    @hooks_json_path = File.join(@dir, "hooks.json")
    FileUtils.rm_rf(PLASTIC_TEST_HOME_CODEX)
    FileUtils.mkdir_p(PLASTIC_TEST_HOME_CODEX)
    @installer = InstallerCore.new(
      package_root: "/tmp/plastic-test-pkg",
      plastic_home: PLASTIC_TEST_HOME_CODEX,
      version: "1.0.0-test",
    )
  end

  def teardown
    FileUtils.rm_rf(@dir)
    FileUtils.rm_rf(PLASTIC_TEST_HOME_CODEX)
  end

  def dispatcher_path
    @installer.codex_dispatcher_path
  end

  def all_commands(data)
    data["hooks"].flat_map do |_event, groups|
      Array(groups).flat_map { |g| Array(g["hooks"]).map { |h| h["command"] } }
    end
  end

  def test_merge_into_empty_hooks_json
    File.write(@hooks_json_path, "{}")
    @installer.merge_codex_hooks(@hooks_json_path)

    data = JSON.parse(File.read(@hooks_json_path))
    expected = HookRegistry.codex_hooks_json(dispatcher_path: dispatcher_path)

    expected.each do |event, groups|
      Array(groups).each do |g|
        expected_commands = g["hooks"].map { |h| h["command"] }
        next if expected_commands.empty?

        matching = Array(data["hooks"][event]).find { |dg| dg["matcher"] == g["matcher"] }
        assert matching, "expected a #{event}/#{g["matcher"].inspect} group in merged output"
        assert_equal expected_commands.sort, matching["hooks"].map { |h| h["command"] }.sort
      end
    end
  end

  def test_merge_twice_produces_no_duplicates
    File.write(@hooks_json_path, "{}")
    @installer.merge_codex_hooks(@hooks_json_path)
    once = JSON.parse(File.read(@hooks_json_path))

    @installer.merge_codex_hooks(@hooks_json_path)
    twice = JSON.parse(File.read(@hooks_json_path))

    assert_equal all_commands(once).size, all_commands(twice).size,
                 "a re-merge must not duplicate entries: #{all_commands(twice).inspect}"
  end

  def test_user_hook_containing_codex_hook_substring_survives_merge
    existing = {
      "hooks" => {
        "PreToolUse" => [
          { "matcher" => "apply_patch", "hooks" => [
            { "type" => "command", "command" => "/Users/test/bin/codex-hook-wrapper --sync" },
          ] },
          { "matcher" => "Bash", "hooks" => [
            { "type" => "command", "command" => "my-codex-hooks activate" },
          ] },
        ],
      },
    }
    File.write(@hooks_json_path, JSON.pretty_generate(existing))
    @installer.merge_codex_hooks(@hooks_json_path)

    data = JSON.parse(File.read(@hooks_json_path))
    commands = all_commands(data)

    assert commands.any? { |c| c.include?("codex-hook-wrapper") }, "codex-hook-wrapper must survive: #{commands.inspect}"
    assert commands.any? { |c| c.include?("my-codex-hooks") }, "my-codex-hooks must survive: #{commands.inspect}"
  end

  # Intent 309: a pre-309 hooks.json (power-tools registered, no SessionEnd) migrates on
  # merge: the retired name is purged and the SessionEnd close group lands.
  def test_pre_309_hooks_json_migrates_on_merge
    existing = {
      "hooks" => {
        "UserPromptSubmit" => [
          { "matcher" => "", "hooks" => [
            { "type" => "command", "command" => "\"#{dispatcher_path}\" capture" },
            { "type" => "command", "command" => "\"#{dispatcher_path}\" power-tools" },
          ] },
        ],
        "SessionStart" => [
          { "matcher" => "", "hooks" => [
            { "type" => "command", "command" => "\"#{dispatcher_path}\" session-start" },
          ] },
        ],
      },
    }
    File.write(@hooks_json_path, JSON.pretty_generate(existing))
    @installer.merge_codex_hooks(@hooks_json_path)

    data = JSON.parse(File.read(@hooks_json_path))
    commands = all_commands(data)
    refute commands.any? { |c| c.include?("power-tools") }, "retired power-tools must be purged: #{commands.inspect}"
    assert commands.any? { |c| c.include?("\" close") }, "SessionEnd close must be registered: #{commands.inspect}"
    refute_nil data["hooks"]["SessionEnd"], "the SessionEnd group must exist after the migration"
    assert_equal 1, commands.count { |c| c.include?("\" capture") }, "no duplicate capture entry: #{commands.inspect}"
  end

  def test_retired_codex_gate_command_is_purged
    existing = {
      "hooks" => {
        "PreToolUse" => [
          { "matcher" => "apply_patch", "hooks" => [
            { "type" => "command", "command" => "\"#{dispatcher_path}\" lock-gate" },
          ] },
        ],
      },
    }
    File.write(@hooks_json_path, JSON.pretty_generate(existing))
    @installer.merge_codex_hooks(@hooks_json_path)

    data = JSON.parse(File.read(@hooks_json_path))
    commands = all_commands(data)

    assert commands.none? { |c| c.include?("lock-gate") }, "retired dispatcher argument must be purged: #{commands.inspect}"
  end

  def test_merge_prints_every_removed_codex_entry
    existing = {
      "hooks" => {
        "PreToolUse" => [
          { "matcher" => "apply_patch", "hooks" => [
            { "type" => "command", "command" => "\"#{dispatcher_path}\" lock-gate" },
          ] },
        ],
      },
    }
    File.write(@hooks_json_path, JSON.pretty_generate(existing))

    original_stdout = $stdout
    output = nil
    begin
      $stdout = StringIO.new
      @installer.merge_codex_hooks(@hooks_json_path)
      output = $stdout.string
    ensure
      $stdout = original_stdout
    end

    assert_includes output, "lock-gate"
  end

  def test_remove_codex_hooks_keeps_user_hook_with_substring
    existing = {
      "hooks" => {
        "PreToolUse" => [
          { "matcher" => "apply_patch", "hooks" => [
            { "type" => "command", "command" => "\"#{dispatcher_path}\" edit-gates" },
            { "type" => "command", "command" => "/Users/test/bin/codex-hook-wrapper --sync" },
          ] },
        ],
      },
    }
    File.write(@hooks_json_path, JSON.pretty_generate(existing))
    @installer.remove_codex_hooks(@hooks_json_path)

    data = JSON.parse(File.read(@hooks_json_path))
    commands = all_commands(data)

    assert commands.none? { |c| c.include?(dispatcher_path) }, "Plastic's dispatcher entry must be removed: #{commands.inspect}"
    assert commands.any? { |c| c.include?("codex-hook-wrapper") }, "user hook must be kept: #{commands.inspect}"
  end

  def test_remove_codex_hooks_returns_nil_on_no_op
    existing = {
      "hooks" => {
        "PreToolUse" => [
          { "matcher" => "apply_patch", "hooks" => [
            { "type" => "command", "command" => "/Users/test/bin/codex-hook-wrapper --sync" },
          ] },
        ],
      },
    }
    File.write(@hooks_json_path, JSON.pretty_generate(existing))
    before = File.read(@hooks_json_path)

    result = @installer.remove_codex_hooks(@hooks_json_path)

    assert_nil result, "a hooks.json with only user entries must be a true no-op"
    assert_equal before, File.read(@hooks_json_path)
  end

  def test_remove_prints_every_removed_codex_entry
    existing = {
      "hooks" => {
        "PreToolUse" => [
          { "matcher" => "apply_patch", "hooks" => [
            { "type" => "command", "command" => "\"#{dispatcher_path}\" edit-gates" },
            { "type" => "command", "command" => "/Users/test/bin/codex-hook-wrapper --sync" },
          ] },
        ],
      },
    }
    File.write(@hooks_json_path, JSON.pretty_generate(existing))

    original_stdout = $stdout
    output = nil
    begin
      $stdout = StringIO.new
      @installer.remove_codex_hooks(@hooks_json_path)
      output = $stdout.string
    ensure
      $stdout = original_stdout
    end

    assert_includes output, "edit-gates"
    assert_includes output, "PreToolUse"
    assert_match(/hooks\.json/, output)
    refute_match(/stale/i, output)
    refute_includes output, "codex-hook-wrapper"
  end

  def test_remove_codex_hooks_prints_nothing_on_no_op
    existing = {
      "hooks" => {
        "PreToolUse" => [
          { "matcher" => "apply_patch", "hooks" => [
            { "type" => "command", "command" => "/Users/test/bin/codex-hook-wrapper --sync" },
          ] },
        ],
      },
    }
    File.write(@hooks_json_path, JSON.pretty_generate(existing))

    original_stdout = $stdout
    output = nil
    result = nil
    begin
      $stdout = StringIO.new
      result = @installer.remove_codex_hooks(@hooks_json_path)
      output = $stdout.string
    ensure
      $stdout = original_stdout
    end

    refute_match(/Removed/, output)
    assert_nil result
  end

  # Intent 275 regression: codex_purge_command? originally split the command
  # on whitespace and took the FIRST token as the dispatcher path. A
  # plastic_home containing a space (a real, if unusual, macOS home directory
  # -- e.g. "/Users/My Name/.plastic") breaks that: the shell-quoted dispatcher
  # path splits across multiple whitespace tokens, so the naive first token is
  # only half the path and never matches. mktmpdir paths never contain a
  # space, which is why this escaped every prior test. Constructing a spaced
  # subdirectory here reproduces the real shape.
  def test_codex_purge_handles_dispatcher_path_containing_a_space
    spaced_home = File.join(@dir, "plastic home")
    FileUtils.mkdir_p(spaced_home)
    installer = InstallerCore.new(package_root: "/tmp/plastic-test-pkg", plastic_home: spaced_home, version: "1.0.0-test")
    dispatcher = installer.codex_dispatcher_path
    assert_includes dispatcher, " ", "fixture assumption: the dispatcher path must contain a space"

    forms = [
      "\"#{dispatcher}\" edit-gates",        # quoted, the exact shape codex_hooks_json emits
      "ruby \"#{dispatcher}\" edit-gates",   # interpreter-prefixed
      "FOO=bar \"#{dispatcher}\" edit-gates", # env-prefixed
    ]

    forms.each do |cmd|
      assert HookRegistry.codex_purge_command?(cmd), "#{cmd.inspect} must be purgeable"
    end

    # Truth table must stay intact: a user command is still never mistaken for ours.
    refute HookRegistry.codex_purge_command?("/Users/test/bin/codex-hook-wrapper --sync")
    refute HookRegistry.codex_purge_command?("my-codex-hooks activate")
  end

  def test_merge_twice_under_spaced_plastic_home_produces_no_duplicates
    spaced_home = File.join(@dir, "plastic home")
    FileUtils.mkdir_p(spaced_home)
    installer = InstallerCore.new(package_root: "/tmp/plastic-test-pkg", plastic_home: spaced_home, version: "1.0.0-test")

    File.write(@hooks_json_path, "{}")
    installer.merge_codex_hooks(@hooks_json_path)
    once = JSON.parse(File.read(@hooks_json_path))

    installer.merge_codex_hooks(@hooks_json_path)
    twice = JSON.parse(File.read(@hooks_json_path))

    assert_equal all_commands(once).size, all_commands(twice).size,
                 "a re-merge under a spaced plastic_home must not duplicate entries: #{all_commands(twice).inspect}"
  end

  # Drift pin: every command codex_hooks_json builds must be matched by
  # codex_purge_command?, with its argument present in codex_purgeable_hook_names
  # (the runtime predicate deliberately does not filter on the argument, per
  # spec.md's rejected alternative -- this test is what guards drift instead).
  def test_every_generated_codex_command_is_purgeable
    commands = HookRegistry.codex_hooks_json(dispatcher_path: dispatcher_path).values.flatten.flat_map do |g|
      g["hooks"].map { |h| h["command"] }
    end
    refute_empty commands

    commands.each do |cmd|
      assert HookRegistry.codex_purge_command?(cmd), "#{cmd} must be purgeable"
      arg = cmd.to_s.split(/\s+/).reject(&:empty?)[1]
      assert_includes HookRegistry.codex_purgeable_hook_names, arg, "#{arg} (from #{cmd}) must be in codex_purgeable_hook_names"
    end
  end
end
