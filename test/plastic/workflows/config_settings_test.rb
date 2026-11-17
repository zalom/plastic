# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/workflows/config_settings"

class ConfigSettingsTest < Plastic::TestCase
  def settings_for(fake, harness: nil)
    Plastic::Workflows::ConfigSettings.new(call_context(declared: %i[harness], settings: fake, harness:))
  end

  def test_the_entries_are_the_ones_of_the_config_the_settings_hold
    fake = FakeSettings.new(values: { "screens" => false })

    assert_equal({ "screens" => false }, settings_for(fake).entries)
  end

  def test_a_value_is_set_through_the_config_the_settings_hold
    fake = FakeSettings.new

    settings_for(fake).set("screens", true)

    assert_equal({ "screens" => true }, fake.written)
  end

  def test_the_problem_is_the_one_the_store_of_the_settings_reports
    assert_equal "the rows changed", settings_for(FakeSettings.new(problem: "the rows changed")).problem
  end

  def test_a_setting_the_config_does_not_hold_is_refused
    error = assert_raises(Plastic::Usage) { settings_for(FakeSettings.new).current("no.such") }

    assert_equal "no setting no.such; plastic config list names them", error.message
  end
end
