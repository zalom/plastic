# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Searches literal indexed passages in the selected local stores.
    class Search < Routine
      argument :terms, label: "TERMS", text: "literal search terms", rest: true
      option :source_projects, switch: "--source-project SLUG", text: "a source store", repeatable: true
      option :limit, switch: "--limit N", text: "maximum passages", default: 20
      reads :knowledge

      workflow :code_search, next: :noop
    end
  end
end
