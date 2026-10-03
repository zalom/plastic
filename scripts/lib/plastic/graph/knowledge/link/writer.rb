# frozen_string_literal: true

require_relative "../link"

module Plastic
  module Graph
    module Knowledge
      class Link
        # Writes and removes one `links` row: a typed edge from one ref to
        # another, an intent id, a ruling ref such as `1/D1`, or a ref with a
        # store prefix such as `global:25`, kept as written.
        class Writer
          def initialize(databases, retrieval)
            @databases = databases
            @retrieval = retrieval
          end

          # Why `id` cannot link to `target`, or nil: a missing id or a local
          # target this store does not hold.
          def target_problem(id, target)
            return "no intent #{id} in this store" unless @retrieval.intent(id)

            local_target_problem(target)
          end

          # Why the link would be refused, or nil: a self link, or one already there.
          def refusal(id, target, kind)
            return "intent #{id} cannot link to itself" if id == target
            return "intent #{id} already has a #{kind} link to #{target}" if linked?(id, target, kind)

            nil
          end

          def add_link(from_ref:, to_ref:, kind:)
            @databases.fetch(:knowledge).transaction do |batch|
              batch.put(:links, { from_ref:, to_ref:, kind:, at: Plastic.now }, statement: :insert)
            end
            true
          end

          def remove_link(from_ref:, to_ref:, kind:)
            database = @databases.fetch(:knowledge)
            written = database.written
            before = written["links"]
            database.transaction { |batch| batch.remove(:links, from_ref:, to_ref:, kind:, origin_id: @retrieval.origin_id) }
            written["links"] > before
          end

          private

          def local_target_problem(target)
            return nil if target.include?(":")

            intent_id, ruling_id = target.split("/", 2)
            return "no intent #{intent_id} in this store" unless @retrieval.intent(intent_id)
            return nil unless ruling_id

            "no ruling #{target} in this store" unless @retrieval.rulings(intent_id).any? { |ruling| ruling.id == ruling_id }
          end

          def linked?(id, target, kind)
            @retrieval.links(id).any? { |link| link.from_ref == id && link.to_ref == target && link.kind == kind }
          end
        end
      end
    end
  end
end
