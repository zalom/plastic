# frozen_string_literal: true

require_relative "../../routine"

module Plastic
  module Commands
    module Project
      # Prints a short digest of each named project: its store and repository,
      # the files to read, the work in play with its passages from the retrieval graph
      # and the last deliveries. It reads the rows and the repository's files and writes nothing.
      class Load < Routine
        opens_no_store
        reads :work, :retrieval

        argument :slugs, label: "SLUG", text: "the projects to load, as words or comma separated; the call's own store when left out",
          rest: true, optional: true

        workflow :code_load_projects, next: :noop
      end
    end
  end
end
