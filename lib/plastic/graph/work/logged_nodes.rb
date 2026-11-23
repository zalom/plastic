# frozen_string_literal: true

require_relative "node_result"

module Plastic
  module Graph
    module Work
      # The node and edge writes that leave a work log line.
      class LoggedNodes
        RESULT_KINDS = { done_node: "done", fail_node: "failed", ask_node: "asked", impede_node: "impeded" }.freeze
        PLAIN_KINDS = { release_node: "released", resolve_node: "resolved", remove_node: "removed" }.freeze
        NODE_KINDS = PLAIN_KINDS.merge(RESULT_KINDS).freeze

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

        def record_run(**fields) = @log.recorded { @writers.nodes.record_run(**fields) }

        def add_edge(intent_id:, from:, to:) = @log.logged(intent_id, "edge_added", "#{from} -> #{to}") { @writers.edges.add_edge(intent_id:, from:, to:) }

        def remove_edge(intent_id:, from:, to:) = @log.logged(intent_id, "edge_removed", "#{from} -> #{to}") { @writers.edges.remove_edge(intent_id:, from:, to:) }

        PLAIN_KINDS.each do |name, kind|
          define_method(name) do |intent_id:, **fields|
            @log.recorded { @writers.nodes.public_send(name, intent_id:, **fields).tap { |node| node && @log.line(intent_id, kind, node.title.to_s, node: node.id) } }
          end
        end

        RESULT_KINDS.each do |name, kind|
          define_method(name) do |intent_id:, files: [], **fields|
            with_result(intent_id, Array(files), kind) { @writers.nodes.public_send(name, intent_id:, **fields) }
          end
        end

        private

        def with_result(intent_id, files, kind, &)
          node, reads = @log.recorded { moved_with_reads(intent_id, files, kind, &) }
          @writers.sync.reprint(reads) if reads.any?
          node
        end

        def moved_with_reads(intent_id, files, kind)
          paths = NodeResult.new(@writers.folder, @writers.retrieval).paths(intent_id, files)
          node = yield
          return [node, []] unless node

          reads = @writers.sync.read_all(paths)
          @log.line(intent_id, kind, node.title.to_s, node: node.id)
          [node, reads]
        end

        def claim_line(intent_id, status, node)
          kind, text = node&.claim_note(status)
          kind && @log.line(intent_id, kind, text, node: node.id)
        end
      end
    end
  end
end
