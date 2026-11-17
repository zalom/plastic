# frozen_string_literal: true

require_relative "log"

module Plastic
  module Graph
    module Work
      # The intent and node writes that leave a work log line: the writer stores its rows,
      # then the log appends one line.
      class LoggedWrites
        NODE_KINDS = { release_node: "released", done_node: "done", fail_node: "failed", ask_node: "asked",
                       impede_node: "impeded", resolve_node: "resolved" }.freeze

        def initialize(writers)
          @writers = writers
          @log = Log.new(writers.databases, writers.retrieval, session: writers.session)
        end

        def write_intent(**intent) = @writers.intents.write(**intent).tap { |found| @log.repair(found.intent_id) }

        def close_intent(intent_id) = @writers.completions.close(intent_id).tap { @log.repair(intent_id) }

        def abandon_intent(intent_id) = @writers.completions.abandon(intent_id).tap { @log.repair(intent_id) }

        def approve_intent(intent_id, **options) = @writers.approvals.approve(intent_id, **options).tap { @log.repair(intent_id) }

        def repair_log(intent_id) = @log.repair(intent_id)

        def add_ruling(intent_id:, **fields)
          @writers.rulings.add_ruling(intent_id:, **fields).tap { |ruling| ruling && @log.record(intent_id, "ruled", "#{ruling.id} #{ruling.text}") }
        end

        def add_verdict(intent_id:, **fields)
          @writers.verdicts.add_verdict(intent_id:, **fields).tap do |verdict|
            verdict && @log.record(intent_id, "verdict", "round #{verdict.round} #{verdict.verdict}: #{verdict.findings}")
          end
        end

        def revise_intent(change)
          @writers.revisions.write(change).tap do
            @log.record(change.intent.intent_id, "wrote", "title: #{change.line}", path: change.document.path, body: change.body)
          end
        end

        def note_intent(intent, kind, text)
          noter.write(intent, kind, text).tap do
            @log.record(intent.intent_id, "noted", "#{kind}: #{text}", path: Knowledge::Intent::Noter::FILE,
              body: @writers.retrieval.fetch(intent.intent_id, Knowledge::Intent::Noter::FILE).body)
          end
        end

        def claim_node(intent_id:, **fields)
          @writers.nodes.claim_node(intent_id:, **fields).tap do |status, node|
            status == :claimed && @log.record(intent_id, "claimed", node.title.to_s, node: node.id)
            status == :capped && @log.record(intent_id, "capped", node.question.to_s, node: node.id)
          end
        end

        NODE_KINDS.each do |name, kind|
          define_method(name) do |intent_id:, **fields|
            @writers.nodes.public_send(name, intent_id:, **fields).tap { |node| node && @log.record(intent_id, kind, node.title.to_s, node: node.id) }
          end
        end

        private

        def noter = (@noter ||= Knowledge::Intent::Noter.new(@writers.databases, @writers.retrieval))
      end
    end
  end
end
