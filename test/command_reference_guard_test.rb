# frozen_string_literal: true

require_relative "command_reference_helper"
require_relative "docs_stale_words_guard_test"

class CommandReferenceGuardTest < Minitest::Test
  include CommandReferenceHelper

  INTENT_ID = DocsStaleWordsGuardTest::INTENT_ID
  DATE = DocsStaleWordsGuardTest::DATE
  FOLDERS = %w[docs/reference/commands docs/reference/dsl].freeze

  def disk = CommandReference::Disk.new(CommandReferenceHelper::ROOT).files

  def stale = CommandReference::Build.stale(CommandReferenceHelper.files, disk)

  def test_the_build_holds_every_command_page_the_index_and_the_dsl_page
    paths = CommandReferenceHelper.files.keys

    assert_equal 71, paths.grep(%r{\Adocs/reference/commands/[^/]+/README\.md\z}).size
    assert_includes paths, "docs/reference/commands/README.md"
    assert_includes paths, "docs/reference/dsl/README.md"
  end

  def test_every_page_on_disk_matches_what_the_code_builds
    assert_empty stale, "run: ruby tools/command-reference, then commit the pages"
  end

  def test_every_folder_under_the_commands_is_a_built_path
    folders = Dir["docs/reference/commands/*/", base: CommandReferenceHelper::ROOT].map { |folder| folder.delete_suffix("/") }
    built = CommandReferenceHelper.files.keys.map { |path| File.dirname(path) }.uniq

    refute_empty folders
    assert_empty folders - built, "run: ruby tools/command-reference"
  end

  def test_no_built_path_holds_a_stale_phrase_an_intent_number_or_a_date
    CommandReferenceHelper.files.each do |path, body|
      [DocsStaleWordsGuardTest::STALE, INTENT_ID, DATE].each { |pattern| assert_empty body.scan(pattern), "#{path} #{pattern}" }
    end
  end

  def test_the_detector_reports_an_edited_text_and_a_missing_file_and_leaves_an_equal_one
    built = { "a" => "same", "b" => "new", "c" => "only built" }

    assert_equal %w[b c], CommandReference::Build.stale(built, { "a" => "same", "b" => "old" })
    assert_empty CommandReference::Build.stale(built, built)
  end

  def test_the_pages_are_listed_in_the_reference_index
    index = File.read(File.join(CommandReferenceHelper::ROOT, "docs/reference/index.md"))

    ["commands/README.md", "dsl/README.md"].each { |page| assert_includes index, page }
  end
end
