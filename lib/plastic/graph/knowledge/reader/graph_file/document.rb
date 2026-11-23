# frozen_string_literal: true

require "json"
require_relative "../../../rows/approval"
require_relative "../../../rows/completion_row"
require_relative "../../../rows/edge"
require_relative "../../../rows/node"
require_relative "../../../rows/run"
require_relative "legacy_nodes"
require_relative "../../../rows/verdict"

module Plastic
  module Graph
    module Knowledge
      class Reader
        class GraphFile
          # The JSON object of a graph file, or the reason the text is not one.
          class Document
            TABLES = {
              approvals: Work::Approval, verdicts: Work::Verdict, nodes: Work::Node, runs: Work::Run, edges: Work::Edge
            }.freeze

            # What a run holds when its graph file came from a release before the harness and the usage were recorded.
            UNRECORDED = { "harness" => "", "worker_session" => "", "usage_note" => "" }.freeze

            PUT_ONLY = { completions: Work::CompletionRow }.freeze

            attr_reader :error

            def initialize(text)
              @error = nil
              @data = parsed(text)
            end

            def valid? = @data.is_a?(Hash)

            def [](key) = @data[key]

            def listed(key) = Array(@data[key])

            def node_ids = listed("nodes").grep(Hash).map { |node| node["id"] }

            def records(table)
              return [@data["approval"]].compact if table == :approvals
              return [@data["completion"]].compact if table == :completions

              table == :runs ? listed("runs").map { |run| UNRECORDED.merge(run) } : listed(table.to_s)
            end

            private

            def parsed(text)
              data = object(JSON.parse(text.dup.force_encoding(Encoding::UTF_8)))
              data && LegacyNodes.new(data).call
            rescue JSON::ParserError => error
              refuse(error.message.lines.first.chomp)
            end

            def object(data) = data.is_a?(Hash) ? data : refuse("it is not an object")

            def refuse(reason)
              @error = reason
              nil
            end
          end
        end
      end
    end
  end
end
