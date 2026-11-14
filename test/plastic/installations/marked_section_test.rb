# frozen_string_literal: true

require_relative "../../test_helper"
require "plastic/installations/marked_section"
require "plastic/installations/codex_instructions"

class MarkedSectionTest < Plastic::TestCase
  MarkedSection = Plastic::Installations::MarkedSection

  def agents_file = File.join(@home, "AGENTS.md")

  def inject(body, kind = MarkedSection::CODEX, path = agents_file) = MarkedSection.new(kind, body).inject(path)

  def test_a_missing_file_is_created_with_the_section
    assert_equal [:created, true], [inject("one"), File.read(agents_file).include?("one")]
  end

  def test_a_section_is_appended_then_replaced_in_place
    File.write(agents_file, "# Mine\n")

    assert_equal %i[appended replaced], [inject("one"), inject("two")]
    assert_equal 1, File.read(agents_file).scan(MarkedSection::CODEX.begin_prefix).size
    assert_includes File.read(agents_file), "# Mine"
  end

  def test_a_file_without_a_closing_newline_still_gets_one_before_the_section
    File.write(agents_file, "# Mine")
    inject("one")

    assert_includes File.read(agents_file), "# Mine\n\n<!-- BEGIN"
  end

  def test_a_section_with_no_end_marker_is_refused
    File.write(agents_file, "#{MarkedSection::CODEX.begin_prefix} -->\nhalf\n")

    assert_equal :refused, inject("one")
  end

  def test_the_two_kinds_do_not_replace_each_other
    inject("codex body")
    inject("claude body", MarkedSection::CLAUDE)

    assert_equal [1, 1], [MarkedSection::CODEX, MarkedSection::CLAUDE].map { |kind| File.read(agents_file).scan(kind.begin_prefix).size }
  end

  def test_a_symlinked_file_keeps_its_link
    target = File.join(@home, "dotfiles.md")
    File.write(target, "# Mine\n")
    File.symlink(target, agents_file)
    inject("one")

    assert_equal [true, true], [File.symlink?(agents_file), File.read(target).include?("one")]
  end

  def test_the_codex_body_points_at_plastic_md
    assert_includes Plastic::Installations::CodexInstructions::BODY, "~/.plastic/PLASTIC.md"
  end
end
