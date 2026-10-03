# frozen_string_literal: true

require_relative "release_helper"

class InstallerReleaseHookStripTest < Minitest::Test
  include ReleaseHelper

  def test_a_settings_file_that_is_not_json_names_the_file_and_stays_as_it_is
    settings = File.join(@root, "settings.json")
    File.write(settings, "{ not json")
    error = assert_raises(JSON::ParserError) { InstallerRelease::HookStrip.new(files: [settings], launchers: []).call }

    assert_equal ["#{settings} is not valid JSON; nothing was changed. Fix the file and run this again.", "{ not json"],
      [error.message, File.read(settings)]
  end
end
