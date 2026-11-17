# frozen_string_literal: true

require_relative "intent_sort"
require_relative "../../../errors"

module Plastic
  module Graph
    module Knowledge
      module Resources
        # What sorting one store folder into the resources layout would do: the moves, the files whose links
        # change and the links it leaves. It reads the folder and writes nothing.
        class SortPlan
          def initialize(folder)
            @folder = folder
          end

          # Refused when a target holds other bytes than the file that would move onto it.
          def moves = (@moves ||= intents.flat_map(&:moves).each { |move| refuse_conflict(move) })

          def empty? = moves.empty?

          def rewrites = intents.flat_map(&:rewrites)

          def unresolved = intents.flat_map(&:unresolved)

          private

          def intents = (@intents ||= @folder.intent_dirs.map { |dir| IntentSort.new(@folder, dir) })

          def refuse_conflict(move)
            return if !@folder.exist?(move.to) || @folder.digest(move.to) == @folder.digest(move.from)

            raise Refused, "#{move.to} already holds other bytes than #{move.from}; move one of them away, then run plastic resources sort again"
          end
        end
      end
    end
  end
end
