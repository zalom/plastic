# frozen_string_literal: true

require_relative "../../command_reference_helper"

class CommandReferencePageFilesTest < Minitest::Test
  include CommandReferenceHelper

  FOLDER = "docs/reference/commands"
  SECTIONS = ["## The workflows of one call", "## The events of one call, step by step", "## What one call changes", "## What the agent workflow steps print"].freeze

  GOES_WITH_THE_STORE = "Goes with the store: the files of the store carry the change, and `plastic store sync up` rebuilds it on another machine. The database files themselves stay on this machine."

  def files_of(words) = CommandReference::PageFiles.new(page(words), "#{FOLDER}/#{page(words).slug}").to_a.to_h { |path, text| [File.basename(path), text] }

  def readme(words) = files_of(words).fetch("README.md")

  def headings(words) = readme(words).lines(chomp: true).select { |line| line.start_with?("## ") }

  def test_the_page_of_intent_end_holds_its_parts_in_order
    text = readme("intent end")
    positions = SECTIONS.map { |heading| text.index("\n#{heading}\n") }

    assert_predicate(positions, :all?, "a section is missing")
    assert_equal positions.sort, positions
    assert text.start_with?("# plastic intent end\n")
  end

  def test_the_page_of_intent_end_ends_with_the_line_that_names_the_class_and_the_file
    last = readme("intent end").lines(chomp: true).reject(&:empty?).last

    assert_match(/\AThe command is `Plastic::Commands::Intent::End`, in \[`commands\/intent\/end\.rb`\]\(.*lib\/plastic\/commands\/intent\/end\.rb\)\.\z/, last)
  end

  def test_no_page_ends_with_a_link_to_a_line_of_the_source
    CommandReferenceHelper.pages.each_value do |each|
      last = readme(each.words).lines(chomp: true).reject(&:empty?).last

      refute_includes last, "#L", each.words
    end
  end

  def test_every_page_names_the_full_class_of_its_command_in_the_last_line
    CommandReferenceHelper.pages.each_value do |each|
      last = readme(each.words).lines(chomp: true).reject(&:empty?).last

      assert_includes last, "`#{each.klass.name}`", each.words
    end
  end

  def test_a_page_with_a_goes_with_the_store_row_defines_the_term_under_its_table
    text = readme("intent end")

    assert_includes text, GOES_WITH_THE_STORE
    assert_operator text.index(GOES_WITH_THE_STORE), :>, text.index("| The intent is marked done")
  end

  def test_every_page_that_says_goes_with_the_store_holds_the_definition_and_no_other_page_does
    CommandReferenceHelper.pages.each_value do |each|
      text = readme(each.words)

      assert_equal text.include?("| goes with the store |"), text.include?(GOES_WITH_THE_STORE), each.words
    end
  end

  def test_a_page_with_several_workflows_has_both_drawings
    assert_equal %w[README.md events.svg workflows.svg], files_of("intent end").keys.sort
  end

  def test_a_page_with_one_workflow_has_no_workflows_drawing_and_no_such_section
    assert_equal %w[README.md events.svg], files_of("node add").keys.sort
    refute_includes headings("node add"), "## The workflows of one call"
  end

  def test_a_page_with_no_agent_step_has_no_agent_texts_section
    refute_includes headings("node add"), "## What the agent workflow steps print"
  end

  def test_every_command_page_has_an_events_drawing
    CommandReferenceHelper.pages.each_value { |each| assert_includes files_of(each.words).keys, "events.svg", each.words }
  end

  def test_the_built_drawings_are_one_events_drawing_per_command_and_one_workflows_drawing_per_command_with_several_workflows
    pages = CommandReferenceHelper.pages.values
    svgs = CommandReferenceHelper.files.keys.grep(%r{\A#{FOLDER}/[^/]+/[^/]+\.svg\z})

    assert_equal pages.size + pages.count { |each| each.flows.size > 1 }, svgs.size
  end

  def test_every_image_of_a_page_is_one_of_its_drawings
    CommandReferenceHelper.pages.each_value do |each|
      files = files_of(each.words)
      images = files["README.md"].scan(/\]\(([\w.-]+\.svg)\)/).flatten

      images.each { |image| assert_includes files.keys, image, each.words }
    end
  end

  def test_a_command_that_changes_nothing_says_so
    text = readme("graph show")

    assert_includes text, "This command changes nothing."
    refute_includes text, "| What changes |"
  end

  def test_the_changes_of_intent_end_are_a_table_with_the_reach_of_each_row
    text = readme("intent end")

    assert_includes text, "| What changes | Where | Reach |"
    assert_match(/\| The intent is marked done, its completion is saved and its driver claim is released \| [^|]+ \| goes with the store \|/, text)
  end

  def test_the_texts_the_agent_reads_show_their_placeholders_in_words
    text = readme("intent end")

    assert_includes text, "<intent id>"
    refute_match(/%\{/, text)
  end

  def test_no_placeholder_of_the_page_of_intent_end_touches_the_next_word
    refute_match(/<[a-z]+(?: [a-z]+)*>[A-Za-z]/, readme("intent end"))
  end

  def test_the_page_names_no_workflow_class_in_a_drawing_or_a_heading
    files_of("intent end").each_value { |text| refute_includes text, "Plastic::Workflows" }
  end
end
