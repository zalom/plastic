# frozen_string_literal: true

require "fileutils"
require_relative "architecture_figures/context"
require_relative "architecture_figures/containers"
require_relative "architecture_figures/components"
require_relative "architecture_figures/graphs"
require_relative "architecture_figures/delivery"
require_relative "architecture_figures/command_call"
require_relative "architecture_figures/node_lifecycle"

# Draws the figures of docs/contributing/ARCHITECTURE.md.
module ArchitectureFigures
  FIGURES = [Context, Containers, Components, Graphs, Delivery, NodeLifecycle, CommandCall].freeze

  def self.diagrams = FIGURES.flat_map(&:diagrams)

  def self.render = Diagram.merge(diagrams)

  def self.build(dir)
    FileUtils.mkdir_p(dir)
    render.each { |name, svg| File.write(File.join(dir, name), svg) }
  end
end
