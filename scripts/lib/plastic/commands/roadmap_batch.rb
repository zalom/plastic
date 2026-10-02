# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Writes one roadmap batch's goal and done criteria.
    class RoadmapBatch < Routine
      subject :slug
      argument :slug, label: "SLUG", text: "the roadmap"
      argument :position, label: "N", text: "the batch's position, 1 and on"
      option :title, switch: "--title TITLE", text: "the batch's title"
      option :goal, switch: "--goal GOAL", text: "the batch's goal"
      option :done, switch: "--done TEXT", text: "one done criterion; repeat for more", repeatable: true
      writes :work

      workflow :code_write_roadmap_batch, next: :noop
    end
  end
end
