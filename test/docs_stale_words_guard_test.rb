# frozen_string_literal: true

require "minitest/autorun"
require_relative "support/stale_words"

class DocsStaleWordsGuardTest < Minitest::Test
  include StaleWords

  ROOT = File.expand_path("..", __dir__)
  PAGES = ["README.md"] + Dir["docs/**/*.md", base: ROOT]
  VARAR = Dir["varar/*.md", base: ROOT] + Dir["test/varar/*.rb", base: ROOT]
  OWNERS = %w[docs/contributing/ARCHITECTURE.md docs/reference/harness-adapters.md].freeze
  LINT_RULES = %w[AGENTS.md docs/contributing/CODING_PRACTICES.md docs/contributing/TECHNICAL.md .reek.yml].freeze
  STALE = /doctor --core|next: none|intent end \S+ --(?!project|json)|\bEvery command ends with/

  def stale_words(text, pattern = STALE) = text.scan(pattern)

  def found(paths, pattern = STALE)
    paths.to_h { |path| [path, stale_words(File.read(File.join(ROOT, path)), pattern)] }.reject { |_, words| words.empty? }
  end

  def test_the_subjects_are_read_from_the_disk
    refute_empty PAGES
    refute_empty VARAR
    OWNERS.each { |page| assert_includes PAGES, page }
  end

  def test_the_lint_rule_files_are_read_from_the_disk
    assert_empty(LINT_RULES.reject { |path| File.file?(File.join(ROOT, path)) })
  end

  def test_no_page_or_acceptance_document_uses_a_removed_option_or_next_line
    assert_empty found(PAGES + VARAR)
  end

  def test_the_owner_pages_name_no_intent_by_number
    assert_empty found(OWNERS, INTENT_ID)
  end

  def test_the_owner_pages_name_no_date
    assert_empty found(OWNERS, DATE)
  end

  def test_the_lint_rules_name_no_date
    assert_empty found(LINT_RULES, DATE)
    assert_empty found(LINT_RULES, LONG_DATE)
  end

  def test_the_long_date_detector_catches_a_written_date_and_leaves_a_month_alone
    assert_equal ["October 3, 2026"], stale_words("frozen since October 3, 2026, in May", LONG_DATE)
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
