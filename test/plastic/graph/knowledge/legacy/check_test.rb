# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeLegacyCheckTest < Plastic::TestCase
  Check = Plastic::Graph::Knowledge::Legacy::Check
  StoreFolder = Plastic::Graph::Knowledge::StoreFolder

  # A store folder whose intent graph file vanishes between listing and reading.
  class VanishingGraph < StoreFolder
    def read(rel) = rel.end_with?("graph.json") ? raise(Errno::ENOENT, rel) : super
  end

  def test_a_store_with_no_index_and_no_files_has_no_problem
    assert_nil Check.new(folder).call
  end

  def test_an_index_that_cannot_be_read_is_named_and_the_other_checks_wait
    skip "a file stays readable to its owner when the owner is root" if Process.uid.zero?
    write("INDEX.md", "# Index\n")
    File.chmod(0o000, folder.path("INDEX.md"))

    error = assert_raises(Check::Failed) { Check.new(folder).call }

    assert_equal "INDEX.md cannot be read", error.message
  ensure
    File.chmod(0o644, folder.path("INDEX.md")) if File.exist?(folder.path("INDEX.md"))
  end

  def test_an_index_with_a_link_under_no_section_is_refused_with_the_reason
    write("INDEX.md", "- [1 - Design](store/1--design/1--design.md)\n")

    error = assert_raises(Check::Failed) { Check.new(folder).call }

    assert_includes error.message, "INDEX.md: "
  end

  def test_a_graph_file_that_vanishes_is_left_for_the_import_to_report
    write("store/1--design/graph.json", "{}")

    assert_nil Check.new(VanishingGraph.new(folder.root)).call
  end
end
