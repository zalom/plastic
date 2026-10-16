# frozen_string_literal: true

require_relative "../../routine"

module Plastic
  module Commands
    module Roadmap
      # Lists a roadmap's loops, dangling edges and items with no intent.
      class Check < Routine
        subject :slug
        argument :slug, label: "SLUG", text: "the roadmap"
        reads :work

        workflow :code_check_roadmap, next: :noop
      end
    end
  end
end
