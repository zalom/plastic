# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "install_fixture"
require "plastic/installations/agent_set"

class AgentSetTest < Plastic::TestCase
  include InstallFixture

  AgentSet = Plastic::Installations::AgentSet

  def set = AgentSet.new(agent_configs)

  def test_the_defaults_name_claude_codex_and_hermes_under_the_home_of_the_person
    defaults = AgentSet::DEFAULTS

    assert_equal [%w[claude codex hermes], File.join(Dir.home, ".codex")], [defaults.map { |agent| agent[:key] }, defaults[1][:home_dir]]
  end

  def test_an_unknown_key_is_not_registered
    refute set.registered?("other")
  end

  def test_a_key_finds_its_agent_and_an_unknown_key_finds_none
    assert_equal ["Codex CLI", nil], [set.config("codex")[:name], set.config("other")]
  end

  def test_the_installed_keys_are_the_agents_whose_record_has_a_version
    write(File.join(fresh, ".hermes", "plastic", "VERSION"), "2.0.0\n")

    assert_equal %w[hermes], set.installed_keys
  end
end

class AgentRecordTest < Plastic::TestCase
  include InstallFixture

  AgentRecord = Plastic::Installations::AgentRecord

  def record(config = claude_config) = AgentRecord.new(config)

  def test_the_record_folder_sits_in_the_agent_folder_and_holds_the_version_and_the_manifest
    claude = record

    assert_equal [File.join(fresh, ".claude", "plastic"), File.join(fresh, ".claude", "plastic", "manifest.json")],
      [claude.dir, claude.manifest.path]
  end

  def test_the_version_is_read_from_the_record_and_is_nil_before_an_install
    assert_nil record.version
    refute_predicate record, :installed?
    record.write_version("2.0.3")

    assert_equal ["2.0.3", true], [record.version, record.installed?]
  end

  def test_a_record_is_registered_when_a_file_its_manifest_lists_exists
    listed = write(File.join(fresh, ".claude", "a.md"), "a\n")
    record.manifest.write([listed])

    assert_predicate record, :registered?
    File.delete(listed)

    refute_predicate record, :registered?
  end

  def test_codex_is_present_where_its_own_home_is_and_the_others_where_their_folder_is
    FileUtils.mkdir_p(File.join(fresh, ".agents"))

    assert_equal [false, File.join(fresh, ".codex"), File.join(fresh, ".claude")],
      [record(codex_config).present?, record(codex_config).presence_dir, record.presence_dir]
  end

  def test_the_former_files_join_the_manifest_and_the_legacy_manifest
    write(File.join(fresh, ".claude", "plastic-manifest.json"), JSON.generate("files" => { "/old/a" => "x" }))
    write(File.join(fresh, ".claude", "plastic", "manifest.json"), JSON.generate("files" => { "/new/b" => "y" }))

    assert_equal %w[/new/b /old/a], record.former_files
  end

  def test_retiring_the_legacy_manifest_deletes_it
    legacy = write(File.join(fresh, ".claude", "plastic-manifest.json"), "{}")
    record.retire_legacy

    refute_path_exists legacy
  end

  def test_the_prune_roots_are_the_folders_of_the_agent_and_the_fragments
    assert_equal [File.join(fresh, ".agents"), File.join(fresh, ".codex"), "/h/_shared.md"], record(codex_config).roots(["/h/_shared.md"])
  end
end
