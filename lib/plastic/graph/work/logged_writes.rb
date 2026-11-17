# frozen_string_literal: true

require_relative "log"

module Plastic
  module Graph
    module Work
      # The intent, node, edge and archive writes that leave a work log line. A write stores its
      # owning rows and one pending row in one transaction, then drains; the next write to the
      # intent drains first, so a line a death cut short is added by it.
      class LoggedWrites
        NODE_KINDS = { release_node: "released", done_node: "done", fail_node: "failed", ask_node: "asked",
                       impede_node: "impeded", resolve_node: "resolved", remove_node: "removed" }.freeze

        def initialize(writers, log: Log.new(writers.databases, writers.retrieval, session: writers.session))
          @writers = writers
          @log = log
        end

        def write_intent(**intent)
          recorded { @writers.intents.write(**intent).tap { |found| @log.stage(found.intent_id, "opened", "Opened: #{found.title}") } }
        end

        def close_intent(intent_id)
          recorded(intent_id) { @writers.completions.close(intent_id).tap { @log.stage(intent_id, "done", "Done") } }
        end

        def abandon_intent(intent_id)
          recorded(intent_id) { @writers.completions.abandon(intent_id).tap { |ran| ran && @log.stage(intent_id, "abandoned", "Abandoned: #{disposition(intent_id)}") } }
        end

        def approve_intent(intent_id, **options)
          recorded(intent_id) do
            given = @writers.retrieval.approval(intent_id)
            @writers.approvals.approve(intent_id, **options).tap { given || @log.stage(intent_id, "approved", "Go-ahead given") }
          end
        end

        def archive_intent(intent_id) = archived(intent_id, "archived") { @writers.archives.archive(intent_id) }

        def unarchive_intent(intent_id) = archived(intent_id, "unarchived") { @writers.archives.restore(intent_id) }

        def drain_log(intent_id) = @log.drain(intent_id)

        def drain_logs = @log.drain_all

        def add_ruling(intent_id:, **fields)
          recorded(intent_id) do
            @writers.rulings.add_ruling(intent_id:, **fields).tap { |ruling| ruling && @log.stage(intent_id, "ruled", "#{ruling.id} #{ruling.text}") }
          end
        end

        def add_verdict(intent_id:, **fields)
          recorded(intent_id) do
            @writers.verdicts.add_verdict(intent_id:, **fields).tap do |verdict|
              verdict && @log.stage(intent_id, "verdict", "round #{verdict.round} #{verdict.verdict}: #{verdict.findings}")
            end
          end
        end

        def revise_intent(change)
          intent_id = change.intent.intent_id
          recorded(intent_id) do
            @writers.revisions.write(change).tap { @log.stage(intent_id, "wrote", "title: #{change.line}", path: change.document.path, body: change.body) }
          end
        end

        def note_intent(intent, kind, text)
          recorded(intent.intent_id) do
            noter.write(intent, kind, text).tap do
              @log.stage(intent.intent_id, "noted", "#{kind}: #{text}", path: Knowledge::Intent::Noter::FILE,
                body: @writers.retrieval.fetch(intent.intent_id, Knowledge::Intent::Noter::FILE).body)
            end
          end
        end

        def add_node(intent_id:, **fields)
          recorded(intent_id) { @writers.nodes.add_node(intent_id:, **fields).tap { |node| node && @log.stage(intent_id, "added", node.title.to_s, node: node.id) } }
        end

        def claim_node(intent_id:, **fields)
          recorded(intent_id) { @writers.nodes.claim_node(intent_id:, **fields).tap { |status, node| claim_line(intent_id, status, node) } }
        end

        def add_edge(intent_id:, from:, to:) = edged(intent_id, "edge_added", from, to) { @writers.edges.add_edge(intent_id:, from:, to:) }

        def remove_edge(intent_id:, from:, to:) = edged(intent_id, "edge_removed", from, to) { @writers.edges.remove_edge(intent_id:, from:, to:) }

        NODE_KINDS.each do |name, kind|
          define_method(name) do |intent_id:, **fields|
            recorded(intent_id) { @writers.nodes.public_send(name, intent_id:, **fields).tap { |node| node && @log.stage(intent_id, kind, node.title.to_s, node: node.id) } }
          end
        end

        private

        def recorded(intent_id = nil, &)
          @log.drain(intent_id) if intent_id
          result = @log.atomically(&)
          @log.drain(intent_id || result.intent_id)
          result
        end

        def archived(intent_id, kind)
          recorded(intent_id) { yield.tap { |ok,| ok && @log.stage(intent_id, kind, kind.capitalize) } }
        end

        def edged(intent_id, kind, from, to)
          recorded(intent_id) { yield.tap { |moved| moved && @log.stage(intent_id, kind, "#{from} -> #{to}") } }
        end

        def claim_line(intent_id, status, node)
          line = { claimed: ["claimed", node&.title], capped: ["capped", node&.question] }[status]
          line && node && @log.stage(intent_id, line.first, line.last.to_s, node: node.id)
        end

        def disposition(intent_id) = @writers.retrieval.intent(intent_id).disposition

        def noter = (@noter ||= Knowledge::Intent::Noter.new(@writers.databases, @writers.retrieval))
      end
    end
  end
end
