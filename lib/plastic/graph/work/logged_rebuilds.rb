# frozen_string_literal: true

module Plastic
  module Graph
    module Work
      # The records an old intent folder gives, written in one transaction with their work log lines: a node for each step,
      # the brief of a step as a packet file listed among the node's inputs, a `noted` line for each session log row, and
      # a ruling for each plan decision. A failed write removes the packet files it wrote.
      class LoggedRebuilds
        PACKETS = File.join(Layout.resource(:tmp), "packets")

        def initialize(writers, log)
          @writers = writers
          @log = log
        end

        # Writes each rebuild, an Intent of the repair, all or none.
        def rebuild_intents(rebuilds)
          written = []
          @log.recorded { rebuilds.each { |rebuild| write(rebuild, written) } }
        rescue
          written.each { |path| @writers.folder.delete(path) }
          raise
        end

        private

        def write(rebuild, written)
          id = rebuild.intent_id
          rebuild.nodes.each { |draft| node(rebuild, draft, written) }
          rebuild.lines.each { |line| @log.line(id, "noted", line.text, at: line.at) }
          rebuild.rulings.each { |text| ruling(id, text) }
        end

        def node(rebuild, draft, written)
          id = rebuild.intent_id
          node = @writers.nodes.add_node(intent_id: id, kind: nil, **draft.to_h.slice(:title, :state, :findings, :reason))
          @log.line(id, "added", node.title.to_s, node: node.id)
          packet(rebuild, node, draft.packet, written) if draft.packet
        end

        def packet(rebuild, node, text, written)
          inside = "#{PACKETS}/#{node.id}.md"
          written << "#{rebuild.dir}/#{inside}"
          @writers.folder.write(written.last, text)
          @writers.databases.fetch(:store).transaction do |batch|
            batch.put(:node_inputs, { intent_id: rebuild.intent_id, node_id: node.id, position: 1, path: inside })
          end
        end

        def ruling(intent_id, text)
          @writers.rulings.add_ruling(intent_id:, text:).tap { |ruling| ruling && @log.line(intent_id, "ruled", "#{ruling.id}: #{ruling.text}") }
        end
      end
    end
  end
end
