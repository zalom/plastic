# frozen_string_literal: true

module Plastic
  module Graph
    module Work
      # The writes that open, move, revise and archive an intent, each leaving its work log line.
      class LoggedIntents
        def initialize(writers, log)
          @writers = writers
          @log = log
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

        def revise_intent(change)
          @log.recorded do
            @writers.revisions.write(change).tap { @log.line(change.intent_id, "wrote", change.title_text, **change.log_fields) }
          end
        end

        private

        def disposition(intent_id) = @writers.retrieval.intent(intent_id).disposition
      end
    end
  end
end
