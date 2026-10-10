# frozen_string_literal: true

module CommandReference
  module Dsl
    # Packs the pieces of one statement into lines no wider than a width.
    class Wrapper
      def initialize(text, width)
        @indent = text[/\A */]
        @pieces = Splitter.new(text.strip).pieces
        @width = width
        @packed = []
      end

      def lines
        @pieces.each { |piece| add(piece) }
        @packed.map { |line| Fitter.new(line, @width).to_s }
      end

      private

      def add(piece) = @packed.empty? ? @packed << "#{@indent}#{piece}" : place(piece)

      def place(piece) = fits?(piece) ? @packed[-1] = "#{@packed.last} #{piece}" : @packed << "#{@indent}  #{piece}"

      def fits?(piece) = @packed.last.size + 1 + piece.size <= @width
    end
  end
end
