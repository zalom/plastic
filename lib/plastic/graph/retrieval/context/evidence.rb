# frozen_string_literal: true

module Plastic
  module Graph
    module Retrieval
      module Context
        # One saved reference of a context, compared with the source state it was
        # saved from.
        class Evidence
          def initialize(document:, reference:, retrieval:)
            @document = document
            @reference = reference
            @retrieval = retrieval
          end

          def state
            archived = retrieval.archived?(current.fetch(:intent_id))
            { "uri" => reference, "state" => fresh?(archived) ? "fresh" : "stale", "archived" => archived }
          end

          private

          attr_reader :document, :reference, :retrieval

          def fresh?(archived) = current.fetch(:uri) == reference && saved_archive(archived) == archived

          def current
            @current ||= begin
              retrieval.fetch_reference(reference)
              retrieval.fetch_reference(reference.sub(/\?revision=[0-9a-f]{64}\z/, ""))
            end
          end

          def saved_archive(archived) = document.fetch("archive_states", {}).fetch(reference, archived)
        end
      end
    end
  end
end
