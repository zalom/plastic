require "minitest/autorun"
require "tmpdir"
require "json"
require "fileutils"

require_relative "../scripts/lib/installer_core"
require_relative "../scripts/lib/engine_permissions"

# The engine deny rule (intent 340b, G7c, n3): a permissions.deny block merged into
# settings.json at install, naming Edit and not Write, covering the four engine
# directories. A second ownership mechanism from HookRegistry's, deliberately: a
# deny entry is a bare string with no marker in it, so ownership is exact-string
# membership in EnginePermissions::ENTRIES.
class EnginePermissionsTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("engine-permissions-test")
    @settings_path = File.join(@dir, "settings.json")
    @home = Dir.mktmpdir("engine-permissions-home")
    @installer = InstallerCore.new(
      package_root: "/tmp/plastic-test-pkg",
      plastic_home: @home,
      version: "1.0.0-test",
    )
  end

  def teardown
    FileUtils.rm_rf(@dir)
    FileUtils.rm_rf(@home)
  end

  def read_settings
    JSON.parse(File.read(@settings_path))
  end

  # Row 3.1
  def test_fresh_install_writes_deny_block
    refute File.exist?(@settings_path)

    @installer.merge_engine_permissions(@settings_path)

    assert File.exist?(@settings_path), "merge_engine_permissions must write settings.json on a fresh install"
    deny = read_settings.dig("permissions", "deny")
    assert_equal EnginePermissions::ENTRIES.sort, deny.sort
  end

  # Row 3.2
  def test_entries_name_edit_only
    EnginePermissions::ENTRIES.each do |entry|
      assert entry.start_with?("Edit("), "#{entry} must name Edit, not Write"
      refute entry.start_with?("Write("), "#{entry} must not name Write: Claude Code never consults it"
    end
  end

  # Row 3.3
  def test_entries_carry_the_recursive_glob
    EnginePermissions::ENTRIES.each do |entry|
      assert entry.end_with?("/**)"), "#{entry} must end in /** or it matches the directory, not its contents"
    end
  end

  # Row 3.4
  def test_all_four_engine_directories_denied
    assert_equal 4, EnginePermissions::ENTRIES.size
    %w[scripts skills hooks templates].each do |subdir|
      assert_includes EnginePermissions::ENTRIES, "Edit(~/.plastic/#{subdir}/**)"
    end
  end

  # Row 3.5
  def test_merge_preserves_user_permissions
    File.write(@settings_path, JSON.generate(
      "permissions" => {
        "allow" => ["Bash(git status)"],
        "ask" => ["Bash(rm:*)"],
      },
    ))

    @installer.merge_engine_permissions(@settings_path)

    permissions = read_settings["permissions"]
    assert_equal ["Bash(git status)"], permissions["allow"]
    assert_equal ["Bash(rm:*)"], permissions["ask"]
    assert_equal EnginePermissions::ENTRIES.sort, permissions["deny"].sort
  end

  # Row 3.6
  def test_merge_is_idempotent
    @installer.merge_engine_permissions(@settings_path)
    @installer.merge_engine_permissions(@settings_path)

    deny = read_settings.dig("permissions", "deny")
    assert_equal EnginePermissions::ENTRIES.size, deny.size
    assert_equal EnginePermissions::ENTRIES.sort, deny.sort
  end

  # Row 3.7
  def test_user_deny_entries_survive
    File.write(@settings_path, JSON.generate(
      "permissions" => { "deny" => ["Bash(curl:*)"] },
    ))

    @installer.merge_engine_permissions(@settings_path)

    deny = read_settings.dig("permissions", "deny")
    assert_includes deny, "Bash(curl:*)"
    EnginePermissions::ENTRIES.each { |entry| assert_includes deny, entry }
    assert_equal EnginePermissions::ENTRIES.size + 1, deny.size
  end

  # Row 3.8
  def test_edited_plastic_entry_is_left_alone_and_reported
    edited = "Edit(~/.plastic/hooks/*.rb)" # the owner narrowed the shipped hooks rule
    File.write(@settings_path, JSON.generate(
      "permissions" => { "deny" => [edited] },
    ))

    @installer.merge_engine_permissions(@settings_path)

    deny = read_settings.dig("permissions", "deny")
    assert_includes deny, edited, "an entry the owner edited is the owner's and must not be reverted"
    assert_includes deny, "Edit(~/.plastic/hooks/**)", "the shipped entry is appended alongside the owner's edit"
    assert_equal EnginePermissions::ENTRIES.size + 1, deny.size
  end

  # Row 3.9
  def test_uninstall_removes_only_plastic_entries
    File.write(@settings_path, JSON.generate(
      "permissions" => { "deny" => EnginePermissions::ENTRIES + ["Bash(curl:*)"] },
    ))

    @installer.remove_engine_permissions(@settings_path)

    deny = read_settings.dig("permissions", "deny")
    assert_equal ["Bash(curl:*)"], deny
  end

  # Row 3.10
  def test_uninstall_prunes_empty_permissions
    File.write(@settings_path, JSON.generate(
      "unrelated" => true,
      "permissions" => { "deny" => EnginePermissions::ENTRIES },
    ))

    @installer.remove_engine_permissions(@settings_path)

    settings = read_settings
    refute settings.key?("permissions"), "an empty husk permissions block must not be left behind"
    assert settings["unrelated"], "unrelated top-level keys must survive"
  end

  # Row 3.11
  def test_unparseable_settings_refuses_the_merge
    original = "{ this is not valid json at all, not even after comment stripping"
    File.write(@settings_path, original)

    result = @installer.merge_engine_permissions(@settings_path)

    refute result, "an unparseable settings file must refuse the merge"
    assert_equal original, File.read(@settings_path), "a hand-edited, unparseable settings file must never be replaced"
  end

  # Row 3.12
  def test_non_hash_permissions_is_replaced_safely
    File.write(@settings_path, JSON.generate("permissions" => "not-a-hash"))

    @installer.merge_engine_permissions(@settings_path)

    permissions = read_settings["permissions"]
    assert_kind_of Hash, permissions
    assert_equal EnginePermissions::ENTRIES.sort, permissions["deny"].sort
  end
end
