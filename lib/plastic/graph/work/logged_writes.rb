# frozen_string_literal: true

require "forwardable"
require_relative "log_writer"
require_relative "logged_nodes"
require_relative "../knowledge/intent/reporter"

module Plastic
  module Graph
    module Work
      # The intent and archive writes that leave a work log line; the node and edge writes are LoggedNodes. A write stores its
      # owning rows and its one work_log row in one transaction, so both land or neither does.
      class LoggedWrites
        extend Forwardable

        def_delegators :@nodes, :add_node, :claim_node, :add_edge, :remove_edge, *LoggedNodes::NODE_KINDS.keys

        def initialize(writers)
          @writers = writers
          @log = LogWriter.new(writers)
          @nodes = LoggedNodes.new(writers, @log)
        end

        def write_intent(**intent)
          @log.recorded { @writers.intents.write(**intent).tap { |found| @log.line(found.intent_id, "opened", "Opened: #{found.title}") } }
        end

        def close_intent(intent_id)
          @log.recorded { @writers.completions.close(intent_id).tap { @log.line(intent_id, "done", "Done") } }
        end

        def abandon_intent(intent_id)
          @log.recorded { @writers.completions.abandon(intent_id).tap { |ran| ran && @log.line(intent_id, "abandoned", "Abandoned: #{disposition(intent_id)}") } }
        end

        def approve_intent(intent_id, **options)
          @log.recorded do
            given = @writers.retrieval.structure.approval(intent_id)
            @writers.approvals.approve(intent_id, **options).tap { given || @log.line(intent_id, "approved", "Go-ahead given") }
          end
        end

        def park_intent(intent_id, reason) = @log.logged(intent_id, "parked", "Parked: #{reason}") { @writers.intents.park(intent_id, reason) }

        def archive_intent(intent_id) = @log.logged(intent_id, "archived", "Archived") { @writers.archives.archive(intent_id) }

        def unarchive_intent(intent_id) = @log.logged(intent_id, "unarchived", "Unarchived") { @writers.archives.restore(intent_id) }

        def add_ruling(intent_id:, **fields)
          @log.recorded do
            @writers.rulings.add_ruling(intent_id:, **fields).tap { |ruling| ruling && @log.line(intent_id, "ruled", "#{ruling.id} #{ruling.text}") }
          end
        end

        def add_verdict(intent_id:, **fields)
          @log.recorded do
            @writers.verdicts.add_verdict(intent_id:, **fields).tap do |verdict|
              verdict && @log.line(intent_id, "verdict", "round #{verdict.round} #{verdict.verdict}: #{verdict.findings}")
            end
          end
        end

        def revise_intent(change)
          @log.recorded do
            @writers.revisions.write(change).tap { @log.line(change.intent_id, "wrote", change.title_text, **change.log_fields) }
          end
        end

        def note_intent(intent, kind, text)
          intent_id = intent.intent_id
          @log.recorded do
            noter.write(intent, kind, text).tap do
              @log.line(intent_id, "noted", "#{kind}: #{text}", path: Knowledge::Intent::Noter::FILE,
                body: @writers.retrieval.fetch(intent_id, Knowledge::Intent::Noter::FILE).body)
            end
          end
        end

        # Writes the `amended` line of one link that the resource sort rewrote in a core file of a closed intent.
        # `path` is the file inside the intent folder and `body` its new text.
        def amend_intent(intent_id, text, path:, body:)
          @log.recorded { @log.line(intent_id, "amended", text, path:, body:) }
        end

        # Records a report of the intent; `text` is Reporter::MANDATORY for a report the setting names, else empty.
        def report_intent(intent, path, text)
          intent_id = intent.intent_id
          @log.recorded do
            reporter.write(intent, path, text).tap do
              @log.line(intent_id, "reported", text, path:, body: reporter.body(intent, path))
            end
          end
        end

        def reporter = (@reporter ||= Knowledge::Intent::Reporter.new(@writers.databases, @writers.retrieval, @writers.folder))

        private

        def disposition(intent_id) = @writers.retrieval.intent(intent_id).disposition

        def noter = (@noter ||= Knowledge::Intent::Noter.new(@writers.databases, @writers.retrieval))
      end
    end
  end
end
