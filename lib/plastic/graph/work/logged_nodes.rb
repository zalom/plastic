# frozen_string_literal: true

module Plastic
  module Graph
    module Work
      # The node and edge writes that leave a work log line.
      class LoggedNodes
        NODE_KINDS = { release_node: "released", done_node: "done", fail_node: "failed", ask_node: "asked",
                       impede_node: "impeded", resolve_node: "resolved", remove_node: "removed" }.freeze

        def initialize(writers, log)
          @writers = writers
          @log = log
        end

        def add_node(intent_id:, **fields)
          @log.recorded { @writers.nodes.add_node(intent_id:, **fields).tap { |node| node && @log.line(intent_id, "added", node.title.to_s, node: node.id) } }
        end

        def claim_node(intent_id:, **fields)
          @log.recorded { @writers.nodes.claim_node(intent_id:, **fields).tap { |status, node| claim_line(intent_id, status, node) } }
        end

        def add_edge(intent_id:, from:, to:) = @log.logged(intent_id, "edge_added", "#{from} -> #{to}") { @writers.edges.add_edge(intent_id:, from:, to:) }

        def remove_edge(intent_id:, from:, to:) = @log.logged(intent_id, "edge_removed", "#{from} -> #{to}") { @writers.edges.remove_edge(intent_id:, from:, to:) }

        NODE_KINDS.each do |name, kind|
          define_method(name) do |intent_id:, **fields|
            @log.recorded { @writers.nodes.public_send(name, intent_id:, **fields).tap { |node| node && @log.line(intent_id, kind, node.title.to_s, node: node.id) } }
          end
        end

        private

        def claim_line(intent_id, status, node)
          kind, text = node&.claim_note(status)
          kind && @log.line(intent_id, kind, text, node: node.id)
        end
      end
    end
  end
end
