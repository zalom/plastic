# frozen_string_literal: true

require_relative "recording_helper"

class InstallationsRecordingCodexTest < Plastic::TestCase
  include RecordingHelper

  def setup
    super
    FileUtils.mkdir_p(File.join(@home, ".codex"))
    installed_into("codex")
  end

  def test_the_record_lists_the_marked_section_of_the_instruction_file
    section = recorded("codex").sections.first

    assert_equal [File.join(@home, ".codex", "AGENTS.md"), "<!-- BEGIN PLASTIC INTEGRATION"], section.values_at("file", "begin")
  end

  def test_the_codex_record_names_the_hooks_file_and_no_status_line
    record = recorded("codex")

    assert_equal [File.join(@home, ".codex", "hooks.json"), nil, []], [record.settings, record.status_line, record.permissions]
  end

  def test_the_record_lists_no_section_when_the_instruction_file_is_gone
    File.delete(File.join(@home, ".codex", "AGENTS.md"))

    assert_empty recorded("codex").sections
  end
end
