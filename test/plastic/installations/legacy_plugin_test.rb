# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "package_fixture"
require "plastic/installations/legacy_plugin"

class LegacyPluginTest < Plastic::TestCase
  include PackageFixture

  def claude = File.join(@home, ".claude")

  def migrate = capture_io { @removed = Plastic::Installations::LegacyPlugin.new(claude).call }.first

  def test_a_legacy_plugin_install_is_migrated_with_a_plain_line
    FileUtils.mkdir_p(File.join(claude, "plugins", "marketplaces", "plastic"))

    assert_includes migrate, "  Migrated legacy plugin install:\n"
    refute_path_exists File.join(claude, "plugins", "marketplaces", "plastic")
  end

  def test_the_plugin_registration_leaves_the_settings_and_the_marketplace_list
    write(File.join(claude, "settings.json"), JSON.generate("enabledPlugins" => { "plastic@plastic" => true }, "extraKnownMarketplaces" => { "plastic" => {}, "mine" => {} }))
    write(File.join(claude, "plugins", "known_marketplaces.json"), JSON.generate("plastic" => {}, "mine" => {}))
    migrate

    assert_equal [{ "extraKnownMarketplaces" => { "mine" => {} } }, { "mine" => {} }],
      %w[settings.json plugins/known_marketplaces.json].map { |name| JSON.parse(File.read(File.join(claude, name))) }
  end

  def test_a_clean_claude_folder_prints_nothing
    FileUtils.mkdir_p(claude)

    assert_equal ["", []], [migrate, @removed]
  end

  def test_a_marketplace_list_without_the_plastic_entry_is_left_as_it_is
    write(File.join(claude, "plugins", "known_marketplaces.json"), JSON.generate("mine" => {}))
    migrate

    assert_equal [{ "mine" => {} }, []], [JSON.parse(File.read(File.join(claude, "plugins", "known_marketplaces.json"))), @removed]
  end

  def test_a_marketplace_list_that_is_no_object_is_left_as_it_is
    write(File.join(claude, "plugins", "known_marketplaces.json"), "[]")
    migrate

    assert_equal [[], []], [JSON.parse(File.read(File.join(claude, "plugins", "known_marketplaces.json"))), @removed]
  end
end
