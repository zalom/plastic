# frozen_string_literal: true

module Plastic
  module Graph
    module Knowledge
      module Repair
        # The totals of a repair, counted apart: the intent folders and their structural changes by kind, the links that
        # change, the `amended` lines, and the links left as they are. A count of nothing is left out. Unless `listed`,
        # the links left as they are print as a count that names the switch that lists them.
        Totals = Data.define(:folders, :links_changed, :amended, :links_left, :listed) do
          # The number with the word for one or for more, or nil for nothing.
          def self.count(number, one, many)
            return if number.zero?

            "#{number} #{(number == 1) ? one : many}"
          end

          def to_s = [changes, Totals.count(links_changed, "link changed", "links changed"), Totals.count(amended, "amended line", "amended lines"), left].compact.join("; ")

          private

          def changes
            return if folders.empty?

            counts = summed
            "#{Totals.count(folders.size, "intent folder", "intent folders")}, #{Totals.count(counts.values.sum, "change", "changes")} (#{kinds(counts)})"
          end

          # The changes of each kind across the folders.
          def summed = folders.map(&:counts).reduce { |sum, counts| sum.merge(counts, &Totals::ADDED) }

          def kinds(counts) = Totals::KINDS.filter_map { |kind, words| Totals.count(counts.fetch(kind), *words) }.join(", ")

          def left
            words = Totals.count(links_left, "link left as it is", "links left as they are")
            (words && !listed) ? "#{words}, which --links-left lists" : words
          end
        end

        # The words of each kind of structural change, for one and for more.
        Totals::ADDED = ->(_, one, other) { one + other }
        Totals::KINDS = { rename: %w[rename renames], move: %w[move moves], remove: %w[removal removals] }.freeze
      end
    end
  end
end
