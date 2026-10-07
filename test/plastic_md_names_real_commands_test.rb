# frozen_string_literal: true

require "minitest/autorun"
require_relative "../scripts/lib/plastic/cli/table"
require_relative "../scripts/lib/installer_core"

# The text that tells an agent which commands exist names only commands that
# exist: PLASTIC.md, the block written to the Codex AGENTS.md and every help
# chapter.
class PlasticMdNamesRealCommandsTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SPAN = /`plastic ([^`]*)`/
  WORD = /\A[a-z][a-z0-9-]*\z/

  def commands = Plastic::CLI::TABLE.keys

  def topics = Dir.glob(File.join(ROOT, "docs", "help", "*.md")).map { |path| File.basename(path, ".md") }

  def words_of(span) = span.split.take_while { |word| word.match?(WORD) }

  def command_named?(words)
    (1..words.size).any? { |size| commands.include?(words.first(size).join(" ")) } || group?(words)
  end

  def group?(words) = words.one? && commands.any? { |name| name.start_with?("#{words.first} ") }

  def help_named?(words) = words.first == "help" && (words.one? || topics.include?(words[1]) || command_named?(words.drop(1)))

  def unknown_names(text)
    text.scan(SPAN).flatten.filter_map do |span|
      words = words_of(span)
      "plastic #{words.join(" ")}" unless words.empty? || command_named?(words) || help_named?(words)
    end
  end

  def bare_unknown_names(text)
    text.scan(/`([a-z][a-z0-9 -]*)`/).flatten.reject { |span| commands.include?(span) || span.start_with?("plastic") }
  end

  def help_files = Dir.glob(File.join(ROOT, "docs", "help", "*.md"))

  def test_the_detector_catches_a_name_that_is_no_command
    assert_equal ["plastic runner step"], unknown_names("Run `plastic runner step 1` and `plastic status`.")
  end

  def test_the_detector_leaves_commands_topics_and_placeholders_alone
    text = "`plastic intent new TITLE`, `plastic help tutorial`, `plastic help TOPIC`, `plastic hook`, `plastic graph resume`"

    assert_empty unknown_names(text)
  end

  def test_the_bare_detector_catches_a_word_that_is_no_command
    assert_equal ["runner step", "answer"], bare_unknown_names("(`runner step`, `status`, `answer`, `plastic`)")
  end

  def test_the_guard_reads_the_help_chapters_from_the_disk
    refute_empty help_files
  end

  def test_plastic_md_names_only_commands_that_exist
    assert_empty unknown_names(File.read(File.join(ROOT, "PLASTIC.md")))
  end

  def test_the_codex_block_names_only_commands_that_exist
    block = InstallerCore::CODEX_AGENTS_MD_BODY

    assert_empty unknown_names(block) + bare_unknown_names(block)
  end

  def test_every_help_chapter_names_only_commands_that_exist
    unknown = help_files.to_h { |path| [File.basename(path), unknown_names(File.read(path))] }.reject { |_name, names| names.empty? }

    assert_empty unknown
  end
end
