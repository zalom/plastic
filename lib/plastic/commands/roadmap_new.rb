# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Creates a roadmap; its batches come from roadmap batch.
    class RoadmapNew < Routine
      subject :slug
      argument :slug, label: "NAME", text: "the roadmap's name"
      option :title, switch: "--title TITLE", text: "the roadmap's title; the name when absent"
      option :goal, switch: "--goal GOAL", text: "the roadmap's goal"
      writes :work
      prints :roadmap

      workflow :code_create_roadmap, next: :noop
    end
  end
end
