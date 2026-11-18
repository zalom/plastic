# frozen_string_literal: true

require_relative "../../test_helper"
require "plastic/installations/package"

class PackageTest < Plastic::TestCase
  Package = Plastic::Installations::Package

  def package(settings) = Package.new("/package", "/home", "2.0.3", settings)

  def test_the_choices_read_the_settings_the_package_was_given
    settings = FakeSettings.new(values: { "advisor.enabled" => false })

    refute_predicate package(settings).choices, :advisor?
  end

  def test_the_hook_entries_read_the_config_of_the_settings_the_package_was_given
    settings = FakeSettings.new

    package(settings).entries

    assert_equal [nil], settings.harnesses
  end
end
