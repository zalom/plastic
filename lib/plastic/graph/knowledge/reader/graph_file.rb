# frozen_string_literal: true

require "json"
require_relative "../../../invalid"
require_relative "../../work/approval"
require_relative "../../work/edge"
require_relative "../../work/node"
require_relative "../../work/verdict"

module Plastic
  module Graph
    module Knowledge
      class Reader
        # The graph.json of one intent folder: the approval, the verdicts, the
        # nodes and the edges. A read replaces the rows of the intent under the
        # local origin; a file that holds a problem writes none.
        class GraphFile
          TABLES = {
            approvals: Work::Approval, verdicts: Work::Verdict, nodes: Work::Node, edges: Work::Edge
          }.freeze

          def initialize(text, intent_id, origin_id, path)
            @text = text
            @intent_id = intent_id
            @origin_id = origin_id
            @path = path
          end

          # One sentence for each reason the file cannot be read.
          def problems
            reasons = data ? [*intent_problems, *approval_problems, *node_problems, *edge_problems, *verdict_problems, *field_problems] : ["is not valid JSON: #{@parse_error}"]
            reasons.map { |reason| "#{@path} #{reason}" }
          end

          def apply(batch)
            found = problems
            raise Invalid, found.join("; ") if found.any?

            TABLES.each_key { |table| batch.remove(table, intent_id: @intent_id, origin_id: @origin_id) }
            rows.each { |table, list| batch.put_all(table, list) }
          end

          private

          def data
            @data ||= begin
              parsed = JSON.parse(@text.dup.force_encoding(Encoding::UTF_8))
              parsed.is_a?(Hash) ? parsed : fail_parse("it is not an object")
            rescue JSON::ParserError => error
              fail_parse(error.message.lines.first.chomp)
            end
          end

          def fail_parse(message)
            @parse_error = message
            nil
          end

          def listed(key) = Array(data[key])

          def nodes = listed("nodes")

          def node_ids = nodes.filter_map { |node| node["id"] if node.is_a?(Hash) }

          def intent_problems
            (data["intent"] == @intent_id) ? [] : ["names intent #{data["intent"].inspect}, not #{@intent_id}"]
          end

          def approval_problems
            approval = data["approval"]
            (approval.nil? || approval.is_a?(Hash)) ? [] : ["holds an approval that is not an object"]
          end

          def node_problems
            nodes.filter_map do |node|
              next "holds a node that is not an object" unless node.is_a?(Hash)

              "holds node #{node["id"].inspect} in the unknown state #{node["state"].inspect}" unless Work::Node::STATES.include?(node["state"])
            end
          end

          def edge_problems
            ends = listed("edges").flat_map { |edge| edge.is_a?(Hash) ? edge.values_at("from", "to") : [edge] }
            (ends - node_ids).uniq.map { |name| "holds an edge to #{name.inspect}, which is no node it holds" }
          end

          def verdict_problems
            listed("verdicts").filter_map do |verdict|
              "holds the verdict #{verdict.inspect}" unless verdict.is_a?(Hash) && Work::Verdict::VERDICTS.include?(verdict["verdict"])
            end
          end

          def field_problems
            TABLES.flat_map { |table, record| unknown_fields(table, record) }
          end

          def unknown_fields(table, record)
            known = record.members.map(&:to_s)
            records(table).filter_map { |entry| "holds the unknown field #{(entry.keys - known).first} in #{table}" if entry.is_a?(Hash) && (entry.keys - known).any? }
          end

          def records(table) = (table == :approvals) ? [data["approval"]].compact : listed(table.to_s)

          def rows
            TABLES.to_h { |table, record| [table, records(table).map { |entry| row(record, entry) }] }
          end

          def row(record, entry)
            keys = record.members - [:origin_id]
            keys.to_h { |key| [key, entry[key.to_s]] }.merge(intent_id: @intent_id, origin_id: @origin_id)
          end
        end
      end
    end
  end
end
