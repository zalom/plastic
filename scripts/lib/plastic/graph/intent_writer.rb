# frozen_string_literal: true

require_relative "intent"
require_relative "intent_ref"
require_relative "store_folder"

module Plastic
  module Graph
    # Writes one new intent: its row, its first savepoint line and its own
    # file, each in the transaction of the database that owns it. The id is
    # the next free Luhmann id, a root or the next child of `parent_id`.
    class IntentWriter
      def initialize(databases, retrieval, folder)
        @databases = databases
        @retrieval = retrieval
        @folder = folder
      end

      # Why the call cannot write the intent, or nil.
      def problem(parent_id: nil, ref: nil, status: "open")
        return "this store still has #{StoreFolder::LEGACY_INDEX}; run plastic sync up to import it first" if @folder.legacy?
        return "#{StoreFolder::INDEX} changed by hand since the last print; run plastic sync up to read it first" if hand_edited?
        return "a new intent takes the status open, active, parked or future, not #{status}" unless Intent::NEW_STATUSES.include?(status)
        return "no intent #{parent_id} in this store to be the parent" if parent_id && !@retrieval.intent(parent_id)

        IntentRef.parse(ref)&.problem(@retrieval)
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
      def ref_line(ref) = IntentRef.parse(ref)&.line(@retrieval.origin_id) || "ref: #{ref}"

      def hand_edited?
        @folder.exist?(StoreFolder::INDEX) && @folder.digest(StoreFolder::INDEX) != @retrieval.printed[StoreFolder::INDEX]
      end

      private

      DEFAULTS = { kind: "work", status: "open" }.freeze

      def write_rows(intent)
        @databases.fetch(:work).transaction do |batch|
          batch.put(:intents, intent.new_row, statement: :insert)
          batch.put(:savepoints, intent.first_savepoint)
        end
        @databases.fetch(:knowledge).transaction { |batch| batch.put(:documents, intent.document(@retrieval.origin_id)) }
      end

      def next_id(parent_id)
        taken = @retrieval.intents.map(&:intent_id)
        parent_id ? LuhmannId.next_child(parent_id, taken) : LuhmannId.next_root(taken)
      end
    end
  end
end
