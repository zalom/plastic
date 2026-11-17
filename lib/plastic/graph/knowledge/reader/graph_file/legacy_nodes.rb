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
            # One node of an older graph file, which gives up its `by` and `retries` and may give one run.
            class Node
              def initialize(node)
                @node = node
              end

              def run_row
                worker = @node.delete("by").to_s
                @node.delete("retries")
                return nil if worker.empty?

                claimed? ? open_run(worker) : closed_run(worker)
              end

              private

              def claimed? = @node["state"] == "claimed"

              def open_run(worker)
                @node.merge!("claimed_by" => worker, "claimed_at" => @node["updated_at"])
                started(worker).merge("ended_at" => nil, "result" => nil)
              end

              def closed_run(worker) = started(worker).merge("ended_at" => @node["updated_at"], "result" => result)

              def started(worker)
                { "node_id" => @node["id"], "number" => 1, "agent" => "", "session_id" => worker, "started_at" => @node["updated_at"] }
              end

              def result
                state = @node["state"]
                (state == "open") ? "released" : state
              end
            end

            def initialize(data)
              @data = data
            end

            def call
              nodes = Array(@data["nodes"]).grep(Hash).select { |node| node.key?("by") || node.key?("retries") }
              return @data if nodes.empty?

              runs = nodes.filter_map { |node| Node.new(node).run_row }
              @data.merge("runs" => Array(@data["runs"]) + runs)
            end
          end
        end
      end
    end
  end
end
