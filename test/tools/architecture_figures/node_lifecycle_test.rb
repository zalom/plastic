# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../support/architecture_figures_helper"
require "architecture_figures"

class ArchitectureFiguresNodeLifecycleTest < Minitest::Test
  include ArchitectureFiguresHelper

  def drawn = texts(ArchitectureFigures.render.fetch("node-lifecycle.svg")).map(&:last)

  def test_the_figure_draws_each_node_state
    assert_empty(%w[open claimed done failed needs_info impeded removed] - drawn)
  end

  def test_the_figure_draws_the_lock_a_claim_keeps_live
    assert_includes drawn, "Delivery lock"
  end
end
