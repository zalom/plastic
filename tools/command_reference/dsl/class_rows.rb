# frozen_string_literal: true

module CommandReference
  module Dsl
    # The lines of one class in a file, unindented to the class line, with their file line numbers.
    class ClassRows
      def initialize(lines, name)
        @lines = lines
        @name = name
      end

      def rows = (start..stop).map { |index| CodeRow.new(index + 1, @lines[index].delete_prefix(indent)) }

      private

      def start = @start ||= @lines.index { |text| text.match?(/^\s*class #{@name}\b/) }

      def indent = @indent ||= @lines[start][/\A */]

      def stop = @stop ||= (start...@lines.size).find { |index| @lines[index] == "#{indent}end" }
    end
  end
end
