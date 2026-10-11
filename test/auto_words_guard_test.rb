# frozen_string_literal: true

require_relative "test_helper"

# Retired auto words guard. `plastic auto ID` is the only auto
# command and the lock is read with `plastic intent lock status ID`, so no
# shipped document and no kernel file names `auto start`, `auto lock`, the
# old `plastic-lock` script or `roadmap start`, which is `roadmap open`. CHANGELOG.md is
# history and keeps the words it was written with.
class AutoWordsGuardTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  RETIRED = /\bauto start\b|\bauto lock\b|\bplastic-lock\b|\broadmap start\b/

  def subjects
    documents = %w[README.md AGENTS.md agents/*.md docs/**/*.md scripts/lib/plastic/**/*.rb]
    Dir.glob(documents, base: ROOT).sort
  end

  def offenses(path)
    File.readlines(File.join(ROOT, path), chomp: true).each_with_index
      .select { |line, _| retired?(line) }
      .map { |line, index| "#{path}:#{index + 1}: #{line.strip}" }
  end

  def retired?(text) = text.match?(RETIRED)

  def test_the_subjects_are_found
    assert_includes subjects, "docs/help/track-2-auto.md"
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
    refute retired?("run plastic auto 7, then plastic intent lock status 7")
  end
end
