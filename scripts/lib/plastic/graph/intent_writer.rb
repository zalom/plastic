# frozen_string_literal: true

require "json"
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

        own_ref_problem(IntentRef.parse(ref))
      end

      def write(title:, parent_id: nil, ref: nil, kind: "work", status: "open", slug: nil)
        now = Plastic.now
        intent = Intent.from_h(intent_id: next_id(parent_id), parent_id:, ref:, slug: slug || Intent.slug_for(title),
          title:, kind:, status:, opened_at: now, updated_at: now)
        @databases.fetch(:work).transaction do |batch|
          batch.put(:intents, intent.to_h.except(:id, :origin_id), new_row: true)
          batch.put(:savepoints, { intent_id: intent.intent_id, position: 1, at: now, text: "Opened: #{title}" })
        end
        @databases.fetch(:knowledge).transaction { |batch| batch.put(:documents, document(intent, now)) }
        @retrieval.intent(intent.intent_id)
      end

      # What a ref names, in words.
      def ref_line(ref)
        found = IntentRef.parse(ref)
        return "ref: #{ref}" unless found
        return "ref: intent #{found.intent_id} of this installation" if found.origin_id == @retrieval.origin_id

        "ref: intent #{found.intent_id} of installation #{found.origin_id}, not in this store"
      end

      def hand_edited?
        @folder.exist?(StoreFolder::INDEX) && @folder.sha256(StoreFolder::INDEX) != @retrieval.printed[StoreFolder::INDEX]
      end

      private

      def own_ref_problem(found)
        return unless found && found.origin_id == @retrieval.origin_id && !@retrieval.intent(found.intent_id)

        "no intent #{found.intent_id} of this installation for the ref"
      end

      def next_id(parent_id)
        taken = @retrieval.intents.map(&:intent_id)
        parent_id ? Intent.next_child(parent_id, taken) : Intent.next_root(taken)
      end

      def document(intent, now) = { intent_id: intent.intent_id, path: intent.file, body: body(intent), updated_at: now }

      def body(intent)
        fields = { id: intent.intent_id, intent: intent.title, parent: intent.parent_id, ref: intent.ref,
                   origin: @retrieval.origin_id, created: intent.opened_at }.compact
        front = fields.map { |name, value| "#{name}: #{JSON.generate(value)}" }
        ["---", *front, "---", "", "# #{intent.intent_id} — #{intent.title}", "", "## Intent", "", intent.title, "",
          "## Context", "", "## Outcome", "", "## Insights", ""].join("\n")
      end
    end
  end
end
