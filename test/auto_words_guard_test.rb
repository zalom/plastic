# frozen_string_literal: true

require_relative "test_helper"

# Retired auto words guard. `plastic intent auto ID` and `plastic roadmap auto SLUG`
# replace the top-level `plastic auto`, and `intent new` takes no status, so no
# shipped document and no kernel file names `plastic auto`, `auto start`, `auto lock`,
# the old `plastic-lock` script, `roadmap start`, which is `roadmap open`, or a status
# or reason option of `intent new`. CHANGELOG.md is history and keeps the words it was
# written with.
class AutoWordsGuardTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  RETIRED = /\bplastic auto\b|\bauto start\b|\bauto lock\b|\bplastic-lock\b|\broadmap start\b|intent new\b.*--(?:status|reason)\b/

  def subjects
    documents = %w[README.md AGENTS.md agents/*.md docs/**/*.md lib/plastic/**/*.rb]
    Dir.glob(documents, base: ROOT).sort
  end

  def offenses(path)
    File.readlines(File.join(ROOT, path), chomp: true).each_with_index
      .select { |line, _| retired?(line) }
      .map { |line, index| "#{path}:#{index + 1}: #{line.strip}" }
  end

  def retired?(text) = text.match?(RETIRED)

  def test_the_subjects_are_found
    assert_includes subjects, "docs/help/roadmaps.md"
  end

  def test_no_subject_names_a_retired_auto_word
    assert_empty subjects.flat_map { |path| offenses(path) }
  end

  def test_the_detector_catches_a_retired_command
    assert retired?("run plastic auto start 7 to arm it")
  end

  def test_the_detector_catches_the_retired_roadmap_command
    assert retired?("run plastic roadmap start r1 a")
  end

  def test_the_detector_leaves_the_new_words_alone
    refute retired?("run plastic intent auto 7, then plastic roadmap auto r1 and plastic intent start 8")
  end

  def test_the_detector_catches_the_retired_top_level_auto
    assert retired?("run plastic auto 7, then plastic intent brief 7")
  end

  def test_the_detector_catches_a_status_option_of_intent_new
    assert retired?("plastic intent new Later --status parked --reason waits")
  end

  def test_the_detector_leaves_the_park_reason_alone
    refute retired?("plastic intent park 7 waits on the review, and plastic intent new Later")
  end
end
