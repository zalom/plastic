# frozen_string_literal: true

module Plastic
  module Graph
    module Knowledge
      class Reader
        class GraphFile
          # Turns the nodes of an older graph file, which named a worker in `by`
          # and counted `retries`, into the nodes and runs the rows hold now. A
          # node with a worker gets one run; a claimed node keeps its claim and
          # its run stays open. The fields `judge` and `verdict`, which a node no
          # longer has, are read past.
          class LegacyNodes
            # One node of an older graph file, which gives up its `by`, `retries`, `judge` and `verdict` and may give one run.
            class Node
              OLD_FIELDS = %w[retries judge verdict].freeze

              def self.old?(hash) = (%w[by] + OLD_FIELDS).any? { |field| hash.key?(field) }

              def initialize(node)
                @node = node
              end

              def run_row
                worker = @node.delete("by").to_s
                OLD_FIELDS.each { |field| @node.delete(field) }
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
              nodes = Array(@data["nodes"]).grep(Hash).select { |node| Node.old?(node) }
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
