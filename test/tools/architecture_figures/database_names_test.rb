# frozen_string_literal: true

require_relative "../../test_helper"
require "architecture_figures"

class ArchitectureFiguresDatabaseNamesTest < Minitest::Test
  DATABASES = %w[plastic.db work_graph.db knowledge_graph.db retrieval_graph.db].freeze

  def databases(figure) = figure.names.select { |kind, _, _| kind == "database" }.map(&:last)

  def test_the_container_figure_names_the_four_database_files
    assert_equal DATABASES, databases(ArchitectureFigures::Containers)
  end

  def test_the_component_figure_names_the_four_database_files
    assert_equal DATABASES, databases(ArchitectureFigures::Components)
  end
end
