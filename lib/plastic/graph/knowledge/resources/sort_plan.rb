# frozen_string_literal: true

require_relative "intent_sort"
require_relative "../../../errors"

module Plastic
  module Graph
    module Knowledge
      module Resources
        # What sorting one store folder into the resources layout would do: the moves, the files whose links
        # change and the links it leaves. It reads the folder and writes nothing. Given the store's `reports`, it also moves
        # each report that is neither recorded nor mandatory to resources/tmp/ and names it.
        class SortPlan
          UNASKED = "neither recorded nor mandatory"

          def initialize(folder, reports: nil)
            @folder = folder
            @reports = reports
          end

          # Refused when a target holds other bytes than the file that would move onto it.
          def moves = (@moves ||= intents.flat_map(&:moves).tap { |all| refuse_conflict(all) })

          def empty? = moves.empty?

          # Every move of the store by old path, the unchecked plan the links are recomputed against.
          def moved = (@moved ||= intents.flat_map(&:moves).to_h { |move| [move.from, move.to] })

          def rewrites = intents.flat_map(&:rewrites)

          def unresolved = intents.flat_map(&:unresolved)

          def changed = intents.flat_map(&:changed)

          # One line for each report the sort moves out of resources/output/reports/.
          def unasked = unasked_moves.map { |move| "moved #{move.from} to #{move.to}: #{UNASKED}" }

          # The line a dry run prints for `move`; the move of a report says why it moves.
          def preview(move) = "preview: move #{move.from} -> #{move.to}#{": #{UNASKED}" if unasked_moves.include?(move)}"

          # The lines a sort of `count` files prints: the count, the links it changed and the links it left.
          def report(count) = ["sorted: #{count} files moved", *unasked, *changed.map { |link| "link changed #{link}" }, *unresolved.map { |link| "link left as it is #{link}" }]

          private

          def unasked_moves = (@unasked_moves ||= intents.flat_map(&:unasked).to_set)

          def refuse_conflict(moves)
            conflicting = moves.find { |move| move.onto_other_bytes?(@folder) }
            raise Refused, conflicting.refusal if conflicting
          end

          def intents = (@intents ||= @folder.intent_dirs.map { |dir| IntentSort.new(@folder, dir, method(:moved), @reports) })
        end
      end
    end
  end
end
