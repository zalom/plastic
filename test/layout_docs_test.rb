# frozen_string_literal: true

require "minitest/autorun"
require_relative "../tools/layout_docs"

# The intent folder section of PLASTIC.md and docs/help/intent-folder.md are generated from lib/plastic/layout.yml.
class LayoutDocsTest < Minitest::Test
  def test_the_docs_page_is_the_page_built_from_the_layout
    assert_equal LayoutDocs.page, File.read(LayoutDocs::PAGE), "run ruby bin/layout-docs"
  end

  def test_the_plastic_section_is_the_section_built_from_the_layout
    assert_equal LayoutDocs.plastic_text, File.read(LayoutDocs::PLASTIC), "run ruby bin/layout-docs"
  end

  def test_the_page_names_every_core_file_every_legacy_name_and_every_root_entry
    names = Plastic::Layout.core_names + Plastic::Layout.legacy.map(&:name) + Plastic::Layout.store_root_allowed.map(&:name) + Plastic::Layout.store_root_legacy.map(&:name)

    assert_empty(names.reject { |name| LayoutDocs.page.include?("`#{name}`") })
  end

  def test_the_section_replaces_itself_and_never_doubles
    once = LayoutDocs.plastic_text(LayoutDocs.plastic_text)

    assert_equal 1, once.scan(LayoutDocs::START).size
  end

  def test_a_changed_page_fails_the_comparison
    refute_equal LayoutDocs.page, "#{LayoutDocs.page}edited"
  end

  def test_a_page_without_the_section_gets_it_after_its_resources_paragraph
    text = LayoutDocs.plastic_text("and whether the result is a finding or code.\nnext\n")

    assert_includes text, LayoutDocs.section
  end

  def test_building_leaves_both_files_as_they_are
    before = [File.read(LayoutDocs::PAGE), File.read(LayoutDocs::PLASTIC)]
    LayoutDocs.build

    assert_equal before, [File.read(LayoutDocs::PAGE), File.read(LayoutDocs::PLASTIC)]
  end
end
