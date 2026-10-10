# frozen_string_literal: true

require "minitest/autorun"
require_relative "support/stale_words"

class DocsStaleWordsGuardTest < Minitest::Test
  include StaleWords

  ROOT = File.expand_path("..", __dir__)
  PAGES = (["README.md"] + Dir["docs/**/*.md", base: ROOT]).reject { |path| path.start_with?("docs/reviews/") }
  VARAR = Dir["varar/*.md", base: ROOT] + Dir["test/varar/*.rb", base: ROOT]
  STALE = /doctor --core|next: none|intent end \S+ --(?!project|json)|\bEvery command ends with/

  def stale_words(text, pattern = STALE) = text.scan(pattern)

  def found(paths, pattern = STALE)
    paths.to_h { |path| [path, stale_words(File.read(File.join(ROOT, path)), pattern)] }.reject { |_, words| words.empty? }
  end

  def test_the_subjects_are_read_from_the_disk
    refute_empty PAGES
    refute_empty VARAR
    assert_equal %w[docs/contributing/ARCHITECTURE.md docs/internals.md], PAGES & %w[docs/contributing/ARCHITECTURE.md docs/internals.md]
  end

  def test_no_page_or_acceptance_document_uses_a_removed_option_or_next_line
    assert_empty found(PAGES + VARAR)
  end

  def test_internals_and_architecture_name_no_intent_by_number
    assert_empty found(["docs/internals.md", "docs/contributing/ARCHITECTURE.md"], INTENT_ID)
  end

  def test_internals_and_architecture_name_no_date
    assert_empty found(["docs/internals.md", "docs/contributing/ARCHITECTURE.md"], DATE)
  end

  def test_the_date_detector_catches_a_date_and_leaves_a_version_alone
    assert_equal ["2026-09-24"], stale_words("removed on 2026-09-24 in version 2.0.3", DATE)
  end

  def test_the_detector_catches_each_stale_phrase
    assert_equal ["doctor --core", "next: none", "intent end 12 --"], stale_words("plastic doctor --core, next: none, plastic intent end 12 --abandoned")
  end

  def test_the_detector_leaves_current_text_alone
    assert_empty stale_words("plastic doctor --store global; plastic intent end 12; no next line")
  end
end
