# frozen_string_literal: true

require_relative "../../routine"

module Plastic
  module Commands
    module Roadmap
      # Prints a roadmap's batches and items from the rows. It reads and writes nothing.
      class Show < Routine
        subject :slug
        argument :slug, label: "SLUG", text: "the roadmap"
        option :position, switch: "--batch N", text: "only this batch"
        reads :work

        workflow :code_show_roadmap, next: :noop
      end
    end
  end
end
