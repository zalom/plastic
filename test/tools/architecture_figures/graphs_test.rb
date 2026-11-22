# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../support/architecture_figures_helper"
require "architecture_figures"

class ArchitectureFiguresGraphsTest < Minitest::Test
  include ArchitectureFiguresHelper

  def drawn = texts(ArchitectureFigures.render.fetch("graphs.svg")).map(&:last)

  def test_the_retrieval_graph_is_drawn_with_its_own_database
    assert_includes drawn, "retrieval_graph.db"
  end

  def test_the_figure_does_not_say_the_retrieval_graph_lives_in_the_knowledge_database
    refute(drawn.any? { |text| text.include?("both live in knowledge_graph.db") })
  end
end
