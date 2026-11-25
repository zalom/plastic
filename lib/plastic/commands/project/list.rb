# frozen_string_literal: true

require_relative "../../routine"

module Plastic
  module Commands
    module Project
      # Lists the projects of projects.yml, each with its path, and marks the
      # ones whose store folder is missing. It writes nothing.
      class List < Routine
        opens_no_store

        workflow :code_list_projects, next: :noop
      end
    end
  end
end
