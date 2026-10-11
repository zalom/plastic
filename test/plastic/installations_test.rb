# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../scripts/lib/plastic/installations"

class InstallationsTest < Plastic::TestCase
  def record(harness = "codex")
    Plastic::Installations::Record.new(harness:, version: "2.0.5", roots: [File.join(@home, ".codex")], files: [],
      folders: [], settings: File.join(@home, ".codex", "hooks.json"), hooks: [], status_line: nil, permissions: [], sections: [])
  end

  def test_a_written_record_reads_back_the_same
    Plastic::Installations.write(@plastic_home, record)

    assert_equal record, Plastic::Installations.read(@plastic_home, "codex")
  end

  def test_each_record_is_one_file_named_after_its_harness
    Plastic::Installations.write(@plastic_home, record)

    assert_path_exists File.join(@plastic_home, "installations", "codex.json")
  end

  def test_a_harness_with_no_record_reads_as_nil
    assert_nil Plastic::Installations.read(@plastic_home, "claude-code")
  end

  def test_the_recorded_harnesses_are_the_registered_ones_with_a_record
    Plastic::Installations.write(@plastic_home, record)
    File.write(File.join(@plastic_home, "installations", "cursor.json"), "{}")

    assert_equal ["codex"], Plastic::Installations.recorded(@plastic_home)
  end
end
