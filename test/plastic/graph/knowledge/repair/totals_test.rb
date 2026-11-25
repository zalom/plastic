# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/graph/knowledge/repair/totals"

# The totals of a repair count the intent folders and their changes apart, leave out a count of nothing, and name the
# switch that lists the links left as they are unless they are listed.
class RepairTotalsTest < Plastic::TestCase
  Totals = Plastic::Graph::Knowledge::Repair::Totals
  Folder = Data.define(:counts)

  def totals(folders: [], listed: false) = Totals.new(folders:, links_changed: 0, amended: 0, links_left: 2, listed:)

  def test_a_repair_with_no_folder_counts_only_the_links_it_left
    assert_equal "2 links left as they are, which --links-left lists", totals.to_s
  end

  def test_listed_links_print_as_a_bare_count
    assert_equal "2 links left as they are", totals(listed: true).to_s
  end

  def test_the_changes_of_each_kind_are_summed_across_the_folders
    folders = [Folder.new({ rename: 1, move: 1, remove: 0, rebuild: 0 }), Folder.new({ rename: 0, move: 2, remove: 1, rebuild: 0 })]

    assert_equal "2 intent folders, 5 changes (1 rename, 3 moves, 1 removal); 2 links left as they are", totals(folders:, listed: true).to_s
  end
end
