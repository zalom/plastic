# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Lists a roadmap's loops, dangling edges and items with no intent.
    class RoadmapCheck < Routine
      subject :slug
      argument :slug, label: "SLUG", text: "the roadmap"
      reads :work

      workflow :code_check_roadmap, next: :noop
    end
  end
end
