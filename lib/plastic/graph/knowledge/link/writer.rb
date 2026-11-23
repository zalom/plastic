# frozen_string_literal: true

require_relative "../link"
require_relative "../intent_needs"

module Plastic
  module Graph
    module Knowledge
      class Link
        # Writes and removes one `links` row: a typed edge from one ref to
        # another, an intent id, a ruling ref such as `1/D1`, or a ref with a
        # store prefix such as `global:25`, kept as written.
        class Writer
          def initialize(databases, retrieval, clock:)
            @databases = databases
            @retrieval = retrieval
            @clock = clock
          end

          # Why `id` cannot link to `target`, or nil: a missing id or a local
          # target this store does not hold.
          def target_problem(id, target)
            return "no intent #{id} in this store" unless @retrieval.intent(id)

            local_target_problem(target)
          end

          # Why the link would be refused, or nil: a self link, one already there, or a needs link to a non-intent or round a loop.
          def refusal(id, target, kind)
            return "intent #{id} cannot link to itself" if id == target
            return "intent #{id} already has a #{kind} link to #{target}" if @retrieval.links(id).any? { |link| link.joins?([id, target, kind]) }

            needs_refusal(id, target) if kind == "needs"
          end

          def add_link(from_ref:, to_ref:, kind:)
            @databases.fetch(:store).transaction do |batch|
              batch.put(:links, { from_ref:, to_ref:, kind:, at: Plastic.timestamp(@clock.now) }, statement: :insert)
            end
            true
          end

          def remove_link(from_ref:, to_ref:, kind:)
            database = @databases.fetch(:store)
            written = database.written
            before = written.dup
            database.transaction { |batch| batch.remove(:links, from_ref:, to_ref:, kind:, origin_id: @retrieval.origin_id) }
            written["links"] > before["links"]
          end

          private

          # Why a needs link is refused, or nil: its target is not an intent of this store, or it would close a loop.
          def needs_refusal(from, to)
            return "a needs link names an intent of this store, not #{to}" unless @retrieval.intent(to)

            cycle = IntentNeeds.new(@retrieval).loop_path(from, to)
            "intent #{from} needing #{to} would close a loop: #{cycle.join(" -> ")}" if cycle
          end

          def local_target_problem(target)
            return nil if target.include?(":")

            intent_id, ruling_id = target.split("/", 2)
            return "no intent #{intent_id} in this store" unless @retrieval.intent(intent_id)
            return nil unless ruling_id

            "no ruling #{target} in this store" unless @retrieval.rulings(intent_id).any? { |ruling| ruling.id == ruling_id }
          end
        end
      end
    end
  end
end
