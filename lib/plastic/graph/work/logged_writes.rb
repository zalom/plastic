# frozen_string_literal: true

require "digest"

module Plastic
  module Graph
    module Work
      # The intent, node, edge and archive writes that leave a work log line. A write stores its
      # owning rows and its one work_log row in one transaction, so both land or neither does.
      class LoggedWrites
        TOP_SQL = "SELECT COALESCE(MAX(position), 0) AS top FROM work_log WHERE intent_id = :intent_id"
        NODE_KINDS = { release_node: "released", done_node: "done", fail_node: "failed", ask_node: "asked",
                       impede_node: "impeded", resolve_node: "resolved", remove_node: "removed" }.freeze

        def initialize(writers)
          @writers = writers
        end

        def write_intent(**intent)
          recorded { @writers.intents.write(**intent).tap { |found| line(found.intent_id, "opened", "Opened: #{found.title}") } }
        end

        def close_intent(intent_id)
          recorded { @writers.completions.close(intent_id).tap { line(intent_id, "done", "Done") } }
        end

        def abandon_intent(intent_id)
          recorded { @writers.completions.abandon(intent_id).tap { |ran| ran && line(intent_id, "abandoned", "Abandoned: #{disposition(intent_id)}") } }
        end

        def approve_intent(intent_id, **options)
          recorded do
            given = @writers.retrieval.approval(intent_id)
            @writers.approvals.approve(intent_id, **options).tap { given || line(intent_id, "approved", "Go-ahead given") }
          end
        end

        def archive_intent(intent_id) = archived(intent_id, "archived") { @writers.archives.archive(intent_id) }

        def unarchive_intent(intent_id) = archived(intent_id, "unarchived") { @writers.archives.restore(intent_id) }

        def add_ruling(intent_id:, **fields)
          recorded do
            @writers.rulings.add_ruling(intent_id:, **fields).tap { |ruling| ruling && line(intent_id, "ruled", "#{ruling.id} #{ruling.text}") }
          end
        end

        def add_verdict(intent_id:, **fields)
          recorded do
            @writers.verdicts.add_verdict(intent_id:, **fields).tap do |verdict|
              verdict && line(intent_id, "verdict", "round #{verdict.round} #{verdict.verdict}: #{verdict.findings}")
            end
          end
        end

        def revise_intent(change)
          intent_id = change.intent.intent_id
          recorded do
            @writers.revisions.write(change).tap { line(intent_id, "wrote", "title: #{change.line}", path: change.document.path, body: change.body) }
          end
        end

        def note_intent(intent, kind, text)
          recorded do
            noter.write(intent, kind, text).tap do
              line(intent.intent_id, "noted", "#{kind}: #{text}", path: Knowledge::Intent::Noter::FILE,
                body: @writers.retrieval.fetch(intent.intent_id, Knowledge::Intent::Noter::FILE).body)
            end
          end
        end

        def add_node(intent_id:, **fields)
          recorded { @writers.nodes.add_node(intent_id:, **fields).tap { |node| node && line(intent_id, "added", node.title.to_s, node: node.id) } }
        end

        def claim_node(intent_id:, **fields)
          recorded { @writers.nodes.claim_node(intent_id:, **fields).tap { |status, node| claim_line(intent_id, status, node) } }
        end

        def add_edge(intent_id:, from:, to:) = edged(intent_id, "edge_added", from, to) { @writers.edges.add_edge(intent_id:, from:, to:) }

        def remove_edge(intent_id:, from:, to:) = edged(intent_id, "edge_removed", from, to) { @writers.edges.remove_edge(intent_id:, from:, to:) }

        NODE_KINDS.each do |name, kind|
          define_method(name) do |intent_id:, **fields|
            recorded { @writers.nodes.public_send(name, intent_id:, **fields).tap { |node| node && line(intent_id, kind, node.title.to_s, node: node.id) } }
          end
        end

        private

        def recorded(&) = store.atomically(&)

        def line(intent_id, kind, text, **parts)
          top = store.row(TOP_SQL, intent_id:).fetch("top")
          store.transaction do |batch|
            batch.put(:work_log, { intent_id:, position: top + 1, at: Plastic.now, phase: "", node: parts.fetch(:node, ""), session_id: @writers.session, kind:, path: parts.fetch(:path, ""),
                                   sha256: parts[:body] ? Digest::SHA256.hexdigest(parts[:body]) : "", text:, origin_id: @writers.retrieval.origin_id })
          end
        end

        def store = @writers.databases.fetch(:store)

        def archived(intent_id, kind)
          recorded { yield.tap { |ok,| ok && line(intent_id, kind, kind.capitalize) } }
        end

        def edged(intent_id, kind, from, to)
          recorded { yield.tap { |moved| moved && line(intent_id, kind, "#{from} -> #{to}") } }
        end

        def claim_line(intent_id, status, node)
          entry = { claimed: ["claimed", node&.title], capped: ["capped", node&.question] }[status]
          entry && node && line(intent_id, entry.first, entry.last.to_s, node: node.id)
        end

        def disposition(intent_id) = @writers.retrieval.intent(intent_id).disposition

        def noter = (@noter ||= Knowledge::Intent::Noter.new(@writers.databases, @writers.retrieval))
      end
    end
  end
end
