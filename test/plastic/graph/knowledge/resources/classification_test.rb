# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/graph/knowledge/resources/classification"

class ResourcesClassificationTest < Plastic::TestCase
  Classification = Plastic::Graph::Knowledge::Resources::Classification

  def destinations(*paths) = paths.map { |path| Classification.destination(path) }

  def test_decide_files_go_to_references
    assert_equal %w[resources/references/ref.md resources/references/sources/a.pdf], destinations("references/ref.md", "resources/sources/a.pdf")
  end

  def test_reviews_packets_and_nodes_go_to_tmp
    assert_equal %w[resources/tmp/reviews/r1.md resources/tmp/packets/p.json resources/tmp/nodes/n1/brief.md],
      destinations("reviews/r1.md", "packets/p.json", "nodes/n1/brief.md")
  end

  def test_legacy_files_have_no_destination
    assert_equal [nil, nil, nil], destinations("plan.md", "checklist.md", "actions/a1.md")
  end

  def test_lock_and_ds_store_files_have_no_destination
    assert_equal [nil, nil, nil, nil], destinations("delivery.lock", "watch.lock", "delivery.write.lock", "resources/.DS_Store")
  end

  def test_the_notes_and_the_sorted_folders_have_no_destination
    assert_equal [nil] * 5, destinations("spec.md", "graph.json", "resources/output/reports/a.md", "resources/references/a.md", "resources/tmp/a.out")
  end

  def test_a_loose_markdown_or_html_file_and_scratch_go_to_tmp_and_other_output_to_files
    assert_equal %w[resources/tmp/notes.md resources/tmp/page.html resources/output/files/data.csv resources/output/files/review.rb resources/tmp/runner-step.last],
      destinations("resources/notes.md", "page.html", "resources/data.csv", "review.rb", "runner-step.last")
  end

  def test_a_file_directly_under_output_is_sorted_by_its_type
    assert_equal %w[resources/tmp/loose.md resources/output/files/loose.csv resources/tmp/loose.out], destinations("resources/output/loose.md", "resources/output/loose.csv", "resources/output/loose.out")
  end
end
