# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "open3"

# Intent 337a (n3): the refused word leaves the seven paths npm publishes. This is the
# shape of subtraction_304_test's forbidden-grammar walk: list every git-tracked file
# under the shipped roots, scan each binary-safe, and assert no whole-word hit survives.
# n4 will widen SCANNED_PATHS to cover test and docs in its own node.
class VocabularyScanTest < Minitest::Test
  REPO = File.expand_path("..", __dir__)

  SCANNED_PATHS = %w[scripts hooks agents skills templates bin PLASTIC.md].freeze

  # Grouped so the word boundary binds the whole alternation, not just the first
  # and last branches (each branch is bounded on both ends this way).
  REFUSED = /\bf(?:old|olds|olded|olding)\b/i

  def test_no_refused_word_in_the_shipped_tree
    offenders = []
    tracked_files.each do |rel|
      path = File.join(REPO, rel)
      next unless File.file?(path)
      raw = File.binread(path)
      text = raw.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
      text.each_line.with_index(1) do |line, n|
        next unless line.match?(REFUSED)
        offenders << "#{rel}:#{n}"
      end
    end
    assert_empty offenders,
      "refused word survives (#{offenders.size}):\n#{offenders.first(30).join("\n")}"
  end

  private

  def tracked_files
    out, _err, status = Open3.capture3("git", "-C", REPO, "ls-files", *SCANNED_PATHS)
    raise "git ls-files failed" unless status.success?
    out.lines.map(&:chomp).reject(&:empty?)
  end
end
