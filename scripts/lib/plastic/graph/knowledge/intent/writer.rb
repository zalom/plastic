# frozen_string_literal: true

require_relative "../intent"
require_relative "ref"
require_relative "../store_folder"
require_relative "../../retrieval/evidence/writer"

module Plastic
  module Graph
    module Knowledge
      class Intent
        # Writes one new intent: its row, its first savepoint line and its own
        # file, each in the transaction of the database that owns it. The id is
        # the next free Luhmann id, a root or the next child of `parent_id`.
        class Writer
          def initialize(databases, retrieval, folder, session: nil)
            @databases = databases
            @retrieval = retrieval
            @folder = folder
            @session = session
          end

          # Why the call cannot write the intent, or nil.
          def problem(parent_id: nil, ref: nil, status: "open")
            return "this store still has #{StoreFolder::LEGACY_INDEX}; run plastic sync up to import it first" if @folder.legacy?
            return "#{StoreFolder::INDEX} changed by hand since the last print; run plastic sync up to read it first" if hand_edited?
            return "a new intent takes the status open, active, parked or future, not #{status}" unless Intent::NEW_STATUSES.include?(status)
            return "no intent #{parent_id} in this store to be the parent" if parent_id && !@retrieval.intent(parent_id)

            Ref.parse(ref)&.problem(@retrieval)
          end

          # `fields` may name the ref, the kind, the status and the slug; a field left out or nil takes its default.
          def write(title:, parent_id: nil, **fields)
            now = Plastic.now
            values = DEFAULTS.merge(fields.compact)
            intent = Intent.from_h(slug: Intent.slug_for(title), **values, intent_id: next_id(parent_id), parent_id:,
              title:, opened_at: now, updated_at: now)
            write_rows(intent)
            @retrieval.intent(intent.intent_id)
          end

          # What a ref names, in words.
          def ref_line(ref) = Ref.parse(ref)&.line(@retrieval.origin_id) || "ref: #{ref}"

          ACTIVATE_SQL = <<~SQL
            UPDATE intents SET status = 'active', updated_at = :now
            WHERE intent_id = :intent_id AND origin_id = :origin AND status NOT IN ('done', 'abandoned')
            RETURNING intent_id
          SQL

          # Sets an open, parked or future intent active; a no-op guard against a
          # race with a status that moved to done or abandoned since the check.
          def activate(intent_id)
            @databases.fetch(:work).transaction do |batch|
              batch.write(:intents, ACTIVATE_SQL, intent_id:, origin: @retrieval.origin_id, now: Plastic.now)
            end
          end

          def hand_edited?
            @folder.exist?(StoreFolder::INDEX) && @folder.digest(StoreFolder::INDEX) != @retrieval.printed[StoreFolder::INDEX]
          end

          private

          DEFAULTS = { kind: "work", status: "open" }.freeze

          def write_rows(intent)
            @databases.fetch(:work).transaction do |batch|
              batch.put(:intents, intent.new_row, statement: :insert)
              batch.put(:savepoints, intent.first_savepoint(@session))
            end
            write_document(intent)
          end

          def write_document(intent)
            origin_id = @retrieval.origin_id
            document = intent.document(origin_id)
            Retrieval::Evidence::Writer.new(@databases.fetch(:knowledge), origin_id).write(*document.values_at(:intent_id, :path, :body))
          end

          def next_id(parent_id)
            taken = @retrieval.intents.map(&:intent_id)
            parent_id ? LuhmannId.next_child(parent_id, taken) : LuhmannId.next_root(taken)
          end
        end
      end
    end
  end
end
