# frozen_string_literal: true

require "minitest/autorun"

class PhasesFigureGuardTest < Minitest::Test
  FIGURE = File.expand_path("../docs/images/intent-lifecycle-phases.svg", __dir__)

  def self.bare_variables(svg) = svg.scan(/var\(--[\w-]+\)/)

  def test_a_variable_without_a_fallback_color_is_caught
    assert_equal ["var(--ink)"], self.class.bare_variables('<g fill="var(--ink)" stroke="var(--line, #6b7483)">')
  end

  def test_the_figure_exists_and_every_variable_carries_a_fallback_color
    svg = File.read(FIGURE)

    assert_includes svg, "var(--"
    assert_empty self.class.bare_variables(svg)
  end

  def test_the_readme_shows_the_figure
    assert_includes File.read(File.expand_path("../README.md", __dir__)), "docs/images/intent-lifecycle-phases.svg"
  end
end
