# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Removes one after edge. Fails when no such edge exists.
    class RoadmapEdgeRemove < Routine
      subject :slug
      argument :slug, label: "SLUG", text: "the roadmap"
      argument :from, label: "FROM", text: "the edge's start"
      argument :to, label: "TO", text: "the edge's end"
      writes :work
      previews

      workflow :code_remove_roadmap_edge, next: :noop
    end
  end
end
