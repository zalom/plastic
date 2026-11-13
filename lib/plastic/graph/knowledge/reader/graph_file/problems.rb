# frozen_string_literal: true

require_relative "document"

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

            def call = [*intent_problems, *approval_problems, *node_problems, *edge_problems, *verdict_problems, *field_problems]

            private

            def intent_problems
              named = @document["intent"]
              (named == @intent_id) ? [] : ["names #{named.nil? ? "no intent" : "intent #{named.inspect}"}, not #{@intent_id}"]
            end

            def approval_problems
              [@document["approval"]].compact.grep_v(Hash).map { "holds an approval that is not an object" }
            end

            def node_problems
              nodes = @document.listed("nodes")
              [*nodes.grep_v(Hash).map { "holds a node that is not an object" }, *state_problems(nodes.grep(Hash))]
            end

            def state_problems(nodes)
              unknown = nodes.map { |node| node.values_at("id", "state") }.reject { |_id, state| Work::Node::STATES.include?(state) }
              unknown.map { |id, state| "holds node #{id.inspect} #{state_phrase(state)}" }
            end

            def state_phrase(state) = state.nil? ? "with no state" : "in the unknown state #{state.inspect}"

            def edge_problems
              ends = @document.listed("edges").flat_map { |edge| edge.is_a?(Hash) ? edge.values_at("from", "to") : [edge] }
              (ends - @document.node_ids).uniq.map { |name| edge_problem(name) }
            end

            def edge_problem(name) = name.nil? ? "holds an edge with no end" : "holds an edge to #{name.inspect}, which is no node it holds"

            def verdict_problems
              unknown = @document.listed("verdicts").reject { |verdict| Work::Verdict::VERDICTS.include?(Hash.try_convert(verdict).to_h["verdict"]) }
              unknown.map { |verdict| "holds the verdict #{verdict.inspect}" }
            end

            def field_problems
              Document::TABLES.flat_map { |table, record| unknown_fields(table, record) }
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
