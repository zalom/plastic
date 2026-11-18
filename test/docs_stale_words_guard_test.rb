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
  STALE = /doctor --core|next: none|intent end \S+ --(?!project|json)|\bEvery command ends with|update --(?:beta|alpha|stable)|next --why|graph show \S+ --dry-run|project new \S+ --path/
  PUBLISHED = PAGES + Dir["{INSTALL,SECURITY,CONTRIBUTING,AGENTS,PLASTIC}.md", "agents/*.md", base: ROOT]
  SCRIPTS = %w[lib/ install-release].freeze
  REMOVED_NAMES = Regexp.union(
    /spawn[- ]preamble|savepoint-note|read-config|delivery\.lock|INDEX\.md|\b(?:plan|checklist|graph)\.md\b|\btemplates\//,
    /plastic (?:auto (?:report|brief)|intent step|session (?:commit|summary|handoff)|migrate|feedback)\b/,
    /(?i:day ledger)/,
    /\bPLASTIC_CHANNEL\b/,
    /\bsync\.(?:media|documents)\b/,
    /brings its own Ruby|jdx\/ruby|(?i:portable Ruby)|downloads? Ruby|with no Ruby on|update check hook|check-update|update-check\.json/,
    %r{\bscripts/(?!#{SCRIPTS.map { |name| Regexp.escape(name) }.join("|")})[a-z]}
  )

  SHIPPED = Dir["{lib,bin,tools,docs}/**/*", base: ROOT].select { |path| File.file?(File.join(ROOT, path)) }

  def stale_words(text, pattern = STALE) = text.scan(pattern)

  def found(paths, pattern = STALE)
    paths.to_h { |path| [path, stale_words(File.read(File.join(ROOT, path)), pattern)] }.reject { |_, words| words.empty? }
  end

  def test_the_shipped_files_are_read_from_the_disk
    assert_includes SHIPPED, "lib/plastic/doctor/core.rb"
    assert_includes SHIPPED, "docs/contributing/figures/containers.svg"
    assert_includes SHIPPED, "tools/store_proof.rb"
  end

  def test_only_the_readers_of_the_old_layout_name_a_word_of_the_old_storage
    assert_empty StaleWords.holding(ROOT, SHIPPED) - StaleWords::OLD_LAYOUT_READERS
  end

  def test_every_allowed_reader_still_holds_a_word_of_the_old_storage
    assert_empty StaleWords::OLD_LAYOUT_READERS - StaleWords.holding(ROOT, StaleWords::OLD_LAYOUT_READERS)
  end

  def test_the_old_layout_detector_catches_a_removed_file_and_database_and_leaves_the_sqlite_savepoint_alone
    caught = stale_words("read savepoint.md and the savepoints table of local.db, then references.db and routine run", StaleWords::OLD_LAYOUT)

    assert_equal ["savepoint.md", "savepoints", "local.db", "references.db", "routine run"], caught
    assert_empty stale_words("db.execute(SAVEPOINT x); old_savepoints.remove; @savepoint_name", StaleWords::OLD_LAYOUT)
  end

  def test_the_removed_storage_detector_catches_each_removed_name_and_leaves_the_current_words_alone
    assert_equal %w[work_log_pending write_id drain_log SchemaHome SchemaStore], stale_words("work_log_pending, write_id, drain_log, SchemaHome, SchemaStore", StaleWords::REMOVED_STORAGE)
    assert_equal ["no ATTACH", "--system"], stale_words("no ATTACH here, ruby bin/test --system", StaleWords::REMOVED_STORAGE)
    assert_empty stale_words("ATTACH is allowed; the work_log table; --systematic", StaleWords::REMOVED_STORAGE)
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

  def test_the_published_pages_include_the_agents_and_the_root_pages
    assert_empty(%w[agents/plastic-executor.md INSTALL.md README.md] - PUBLISHED)
  end

  def test_no_published_page_names_a_removed_script_command_or_file
    assert_empty found(PUBLISHED, REMOVED_NAMES)
  end

  def test_the_removed_names_detector_catches_an_old_command_and_leaves_its_successor_alone
    assert_equal [["plastic auto brief"], []], [stale_words("run plastic auto brief 12", REMOVED_NAMES), stale_words("run plastic intent brief 12", REMOVED_NAMES)]
  end

  def test_the_removed_names_detector_catches_the_channel_variable_and_leaves_the_update_option_alone
    assert_equal [["PLASTIC_CHANNEL"], []], [stale_words("install.sh | PLASTIC_CHANNEL=alpha sh", REMOVED_NAMES), stale_words("plastic update --channel alpha", REMOVED_NAMES)]
  end

  def test_the_removed_names_detector_catches_the_ruby_download_and_the_update_check_hook_and_leaves_the_ruby_requirement_alone
    caught = stale_words("install.sh brings its own Ruby; the update check hook reads check-update from jdx/ruby", REMOVED_NAMES)

    assert_equal ["brings its own Ruby", "update check hook", "check-update", "jdx/ruby"], caught
    assert_empty stale_words("Plastic needs Ruby 4.0 or later and git; plastic update reads the release list", REMOVED_NAMES)
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

  def test_the_detector_catches_an_option_a_command_does_not_have
    text = "plastic update --beta, plastic update --channel beta, plastic next --why, plastic graph show 12 --dry-run, plastic project new app --path /x"

    assert_equal ["update --beta", "next --why", "graph show 12 --dry-run", "project new app --path"], stale_words(text)
  end

  def test_the_detector_leaves_current_text_alone
    assert_empty stale_words("plastic doctor --store global; plastic intent end 12; no next line")
  end
end
