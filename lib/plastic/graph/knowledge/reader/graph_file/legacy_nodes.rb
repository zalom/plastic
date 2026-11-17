# frozen_string_literal: true

module Plastic
  module Graph
    module Knowledge
      class Reader
        class GraphFile
          # Turns the nodes of an older graph file, which named a worker in `by`
          # and counted `retries`, into the nodes and runs the rows hold now. A
          # node with a worker gets one run; a claimed node keeps its claim and
          # its run stays open.
          class LegacyNodes
            def initialize(data)
              @data = data
            end

            def call
              nodes = Array(@data["nodes"]).grep(Hash).select { |node| node.key?("by") || node.key?("retries") }
              return @data if nodes.empty?

              runs = nodes.filter_map { |node| convert(node) }
              @data.merge("runs" => Array(@data["runs"]) + runs)
            end

            private

            def convert(node)
              worker = node.delete("by").to_s
              node.delete("retries")
              return nil if worker.empty?

              claimed = node["state"] == "claimed"
              node.merge!("claimed_by" => worker, "claimed_at" => node["updated_at"]) if claimed
              run_row(node, worker, claimed)
            end

            def run_row(node, worker, claimed)
              { "node_id" => node["id"], "number" => 1, "agent" => "", "session_id" => worker, "started_at" => node["updated_at"],
                "ended_at" => (node["updated_at"] unless claimed), "result" => (result(node) unless claimed) }
            end

            def result(node) = (node["state"] == "open") ? "released" : node["state"]
          end
        end
      end
    end
  end
end
