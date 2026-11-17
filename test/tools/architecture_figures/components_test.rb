# frozen_string_literal: true

require_relative "../../test_helper"
require "architecture_figures"

class ArchitectureFiguresComponentsTest < Minitest::Test
  def test_the_component_figure_names_the_four_database_files
    databases = ArchitectureFigures::Components.names.select { |kind, _, _| kind == "database" }.map(&:last)

    assert_equal %w[plastic.db work_graph.db knowledge_graph.db retrieval_graph.db], databases
  end
end
