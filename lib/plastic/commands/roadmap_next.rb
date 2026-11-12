# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Prints the first ready item of a roadmap, or what is in the way.
    class RoadmapNext < Routine
      subject :slug
      argument :slug, label: "SLUG", text: "the roadmap"
      option :position, switch: "--batch N", text: "only this batch"
      reads :work

      workflow :code_next_roadmap, next: :noop
    end
  end
end
