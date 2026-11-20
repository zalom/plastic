# frozen_string_literal: true

require_relative "intent_sort"
require_relative "../../../errors"

module Plastic
  module Graph
    module Knowledge
      module Resources
        # What sorting one store folder into the resources layout would do: the moves, the files whose links
        # change and the links it leaves. It reads the folder and writes nothing. Given the store's `reports`, it also moves
        # each report that is neither recorded nor mandatory to resources/tmp/ and names it. Each link it rewrites in a core
        # file of an intent of `closed`, the ids of the done and abandoned intents, is an amendment.
        class SortPlan
          UNASKED = "neither recorded nor mandatory"

          # The ids of the done and abandoned intents of `retrieval`.
          def self.closed(retrieval) = retrieval.intents.select(&:closed?).to_set(&:intent_id)

          def initialize(folder, reports: nil, closed: Set.new)
            @folder = folder
            @reports = reports
            @closed = closed
          end

          # Refused when a target holds other bytes than the file that would move onto it.
          def moves = (@moves ||= intents.flat_map(&:moves).tap { |all| refuse_conflict(all) })

          def empty? = moves.empty?

          # Every move of the store by old path, the unchecked plan the links are recomputed against.
          def moved = (@moved ||= intents.flat_map(&:moves).to_h { |move| [move.from, move.to] })

          # The store paths that a recorded or mandatory report of any intent links to: none of them moves.
          def kept = (@kept ||= intents.flat_map { |intent| intent.listed_targets.to_a }.to_set)

          def rewrites = intents.flat_map(&:rewrites)

          def unresolved = intents.flat_map(&:unresolved)

          def changed = intents.flat_map(&:changed)

          def amendments = intents.flat_map(&:amendments).select { |amendment| @closed.include?(amendment.intent_id) }

          # One line for each report the sort moves out of resources/output/reports/.
          def unasked = unasked_moves.map { |move| "moved #{move.from} to #{move.to}: #{UNASKED}" }

          # The line a dry run prints for `move`; the move of a report says why it moves.
          def preview(move) = "preview: move #{move.from} -> #{move.to}#{": #{UNASKED}" if unasked_moves.include?(move)}"

          # The lines a sort of `count` files prints: the count, the links it changed, the amendments and the links it left.
          def report(count)
            ["sorted: #{count} files moved", *unasked, *changed.map { |link| "link changed #{link}" }, *amendments.map(&:line),
              *unresolved.map { |link| "link left as it is #{link}" }]
          end

          private

          def unasked_moves = (@unasked_moves ||= intents.flat_map(&:unasked).to_set)

          def refuse_conflict(moves)
            conflicting = moves.find { |move| move.onto_other_bytes?(@folder) }
            raise Refused, conflicting.refusal if conflicting
          end

          def intents = (@intents ||= @folder.intent_dirs.map { |dir| IntentSort.new(@folder, dir, self, @reports) })
        end
      end
    end
  end
end
