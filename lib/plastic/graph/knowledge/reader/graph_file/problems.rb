# frozen_string_literal: true

require_relative "document"
require_relative "wording"

module Plastic
  module Graph
    module Knowledge
      class Reader
        class GraphFile
          # The reasons a parsed graph file cannot be read into rows.
          class Problems
            def initialize(document, intent_id)
              @document = document
              @intent_id = intent_id
            end

            def call = [*intent_problems, *approval_problems, *completion_problems, *node_problems, *edge_problems, *verdict_problems, *field_problems]

            private

            def intent_problems
              named = @document["intent"]
              (named == @intent_id) ? [] : ["names #{Wording.intent(named)}, not #{@intent_id}"]
            end

            def approval_problems
              [@document["approval"]].compact.grep_v(Hash).map { "holds an approval that is not an object" }
            end

            def completion_problems
              entry = @document["completion"]
              return [] unless entry
              return ["holds a completion that is not an object"] unless entry.is_a?(Hash)

              completion_named(entry["intent_id"])
            end

            def completion_named(named) = (named == @intent_id) ? [] : ["holds a completion of #{Wording.intent(named)}, not #{@intent_id}"]

            def node_problems
              nodes = @document.listed("nodes")
              [*nodes.grep_v(Hash).map { "holds a node that is not an object" }, *state_problems]
            end

            def state_problems
              unknown = @document.listed("nodes").grep(Hash).map { |node| node.values_at("id", "state") }.reject { |_id, state| Work::Node::STATES.include?(state) }
              unknown.map { |id, state| "holds node #{id.inspect} #{Wording.state(state)}" }
            end

            def edge_problems
              ends = @document.listed("edges").flat_map { |edge| edge.is_a?(Hash) ? edge.values_at("from", "to") : [edge] }
              (ends - @document.node_ids).uniq.map { |name| "holds an edge #{Wording.edge(name)}" }
            end

            def verdict_problems
              unknown = @document.listed("verdicts").reject { |verdict| Work::Verdict::VERDICTS.include?(Hash.try_convert(verdict).to_h["verdict"]) }
              unknown.map { |verdict| "holds the verdict #{verdict.inspect}" }
            end

            def field_problems
              Document::TABLES.merge(Document::PUT_ONLY).flat_map { |table, record| unknown_fields(table, record) }
            end

            def unknown_fields(table, record)
              known = record.members.map(&:to_s)
              extra = @document.records(table).grep(Hash).map { |entry| entry.keys - known }
              extra.reject(&:empty?).map { |fields| "holds the unknown field #{fields.first} in #{table}" }
            end
          end
        end
      end
    end
  end
end
