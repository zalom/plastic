# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../support/architecture_figures_helper"
require "architecture_figures"

class ArchitectureFiguresContextTest < Minitest::Test
  include ArchitectureFiguresHelper

  def drawn = texts(ArchitectureFigures.render.fetch("context.svg")).map(&:last)

  def test_the_figure_says_the_owner_reviews_the_pull_request_when_review_is_on
    assert_includes drawn, "reviews the pull request when review is on"
  end

  def test_the_figure_does_not_say_the_owner_merges
    refute(drawn.any? { |text| text.include?("and merges") })
  end
end
