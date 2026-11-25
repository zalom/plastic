# frozen_string_literal: true

module ArchitectureFigures
  class Diagram
    # The boxes of a figure, read from a table of text rows.
    module Rows
      COLUMNS = %i[type geometry name kind tone mono lines].freeze
      GEOMETRY = %i[left top width height].freeze

      def self.parse(table)
        table.lines.to_h do |row|
          key, *cells = row.split("|").map(&:strip)
          [key.to_sym, attributes(COLUMNS.zip(cells).to_h)]
        end
      end

      def self.attributes(cells)
        words = cells.slice(:name, :kind, :type, :tone).reject { |_column, word| word.to_s.empty? }
        GEOMETRY.zip(cells[:geometry].split.map(&:to_i)).to_h.compact.merge(words, words.slice(:type, :tone).transform_values(&:to_sym), extras(cells))
      end

      def self.extras(cells)
        lines = cells[:lines].to_s.split(" / ")
        { mono: (true if cells[:mono] == "mono"), lines: (lines unless lines.empty?) }.compact
      end
    end
  end
end
