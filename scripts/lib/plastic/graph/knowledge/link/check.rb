# frozen_string_literal: true

require_relative "../link"

module Plastic
  module Graph
    module Knowledge
      class Link
        # Reads every link of the store and names the ones whose local end
        # holds no intent or no ruling. A ref with a store prefix, such as
        # `other:5`, names another store and is left alone.
        class Check
          ALL_SQL = "SELECT * FROM links WHERE origin_id = :origin ORDER BY from_ref, to_ref, kind"

          def initialize(databases, retrieval)
            @databases = databases
            @retrieval = retrieval
          end

          def broken = links.reject { |link| resolves?(link.from_ref) && resolves?(link.to_ref) }

          private

          def links = @databases.fetch(:knowledge).rows(ALL_SQL, origin: @retrieval.origin_id).map { |row| Link.from_h(row) }

          def resolves?(ref)
            return true if ref.include?(":")

            intent_id, ruling_id = ref.split("/", 2)
            return false unless intents.include?(intent_id)

            ruling_id.nil? || @retrieval.rulings(intent_id).any? { |ruling| ruling.id == ruling_id }
          end

          def intents = (@intents ||= @retrieval.intents.map(&:intent_id))
        end
      end
    end
  end
end
