# frozen_string_literal: true

require_relative "../../command_reference_helper"

class CommandReferenceBuildTest < Minitest::Test
  include CommandReferenceHelper

  def test_two_builds_return_equal_hashes
    assert_equal CommandReferenceHelper.files, CommandReference::Build.new(CommandReferenceHelper::ROOT).files
  end

  def test_no_built_text_holds_the_root_or_the_home_directory
    CommandReferenceHelper.files.each do |path, body|
      refute_includes body, CommandReferenceHelper::ROOT, path
      refute_includes body, Dir.home, path
    end
  end

  def test_the_build_holds_a_page_per_command_the_index_and_the_dsl_page
    paths = CommandReferenceHelper.files.keys

    assert_equal 76, paths.grep(%r{\Adocs/reference/commands/[^/]+/README\.md\z}).size
    assert_includes paths, "docs/reference/commands/README.md"
    assert_includes paths, "docs/reference/dsl/README.md"
  end

  def test_every_built_path_is_under_the_two_reference_folders
    assert(CommandReferenceHelper.files.keys.all? { |path| path.start_with?("docs/reference/commands/", "docs/reference/dsl/") })
  end

  def test_every_markdown_image_is_a_built_file
    CommandReferenceHelper.files.select { |path, _| path.end_with?(".md") }.each do |path, body|
      body.scan(/\]\(([\w.-]+\.svg)\)/).flatten.each { |image| assert CommandReferenceHelper.files.key?(File.join(File.dirname(path), image)), "#{path}: #{image}" }
    end
  end

  def test_stale_reports_an_edited_text_a_missing_file_and_an_extra_file_but_not_an_equal_one
    built = { "a.md" => "one", "b.md" => "two", "c.md" => "three" }
    disk = { "a.md" => "one", "b.md" => "edited", "d.md" => "left over" }

    assert_equal %w[b.md c.md d.md], CommandReference::Build.stale(built, disk)
    assert_empty CommandReference::Build.stale(built, built)
  end
end
