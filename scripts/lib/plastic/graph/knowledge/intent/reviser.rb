# frozen_string_literal: true

require_relative "revision"
require_relative "../store_folder"
require_relative "../../retrieval/evidence/writer"

module Plastic
  module Graph
    module Knowledge
      class Intent
        # Rewrites an intent's What and Why: a new revision of its own file in
        # the knowledge graph, then its title row. The old revision row stays,
        # so the old text reads back by its qualified reference.
        class Reviser
          # One revise of one intent: the file row it starts from, and the new What and Why.
          Change = Data.define(:intent, :document, :line, :why) do
            def path = "#{intent.dir}/#{intent.file}"

            def revision = Revision.new(document.body, intent.intent_id)

            def old_why = revision.why

            def body = revision.revise(line, why)

            def same? = line == intent.title && body == document.body
          end

          TITLE_SQL = <<~SQL
            UPDATE intents SET title = :title, updated_at = :now
            WHERE intent_id = :intent_id AND origin_id = :origin AND status NOT IN ('done', 'abandoned')
          SQL

          def initialize(databases, retrieval, folder)
            @databases = databases
            @retrieval = retrieval
            @folder = folder
          end

          # The change, or nil when the intent has no file row.
          def change(intent, line, why)
            document = @retrieval.fetch(intent.intent_id, intent.file)
            document && Change.new(intent:, document:, line:, why:)
          end

          # Why the change cannot be written, or nil.
          def problem(change) = line_problem(change.line) || edit_problem(change) || same_problem(change)

          # Writes the change and returns the qualified references of the old and the new revision.
          def write(change)
            intent_id = change.intent.intent_id
            path = change.intent.file
            old = @retrieval.reference(intent_id, path)
            Retrieval::Evidence::Writer.new(@databases.fetch(:knowledge), @retrieval.origin_id).write(intent_id, path, change.body)
            write_title(intent_id, change.line)
            [old, @retrieval.reference(intent_id, path)].map { |reference| reference.fetch(:uri) }
          end

          private

          def line_problem(line)
            "the new What is one line; it holds a line break" if line.include?("\n")
          end

          def edit_problem(change)
            printed = @retrieval.printed
            edited = [change.path, StoreFolder::INDEX].find { |path| @folder.exist?(path) && @folder.digest(path) != printed[path] }
            "#{edited} changed by hand since the last print; run plastic sync up first" if edited
          end

          def same_problem(change)
            "intent #{change.intent.intent_id} already reads this What and Why; nothing to change" if change.same?
          end

          def write_title(intent_id, title)
            @databases.fetch(:work).transaction do |batch|
              batch.write(:intents, TITLE_SQL, title:, intent_id:, origin: @retrieval.origin_id, now: Plastic.now)
            end
          end
        end
      end
    end
  end
end
