# frozen_string_literal: true

require_relative "recording_helper"

class InstallationsRecordingHermesTest < Plastic::TestCase
  include RecordingHelper

  def setup
    super
    FileUtils.mkdir_p(File.join(@home, ".hermes"))
    installed_into("hermes")
  end

  def test_the_hermes_record_lists_the_skills_and_agents_it_copied
    files = recorded("hermes").files

    assert_includes files, File.join(@home, ".hermes", "plastic", "VERSION")
    assert(files.any? { |file| file.start_with?(File.join(@home, ".hermes", "agents", "plastic-")) })
  end

  def test_the_hermes_record_names_no_settings_file_and_no_section
    record = recorded("hermes")

    assert_equal [nil, [], nil, [], []], [record.settings, record.hooks, record.status_line, record.permissions, record.sections]
  end
end
