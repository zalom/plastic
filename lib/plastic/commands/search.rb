# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Searches the indexed passages of the selected local stores for the words of a question, best match first.
    class Search < Routine
      argument :terms, label: "TERMS", text: "the words of a question, ranked by BM25; quote a phrase to keep it whole", rest: true
      option :source_projects, switch: "--source-project SLUG", text: "a source store", repeatable: true
      option :limit, switch: "--limit N", text: "maximum passages", default: 20
      reads :knowledge, :retrieval

      workflow :code_search, next: :noop
    end
  end
end
