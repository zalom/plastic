# frozen_string_literal: true

module Plastic
  class Context
    # The printed entries of one call, in the order they were printed.
    class Printed
      # One printed line.
      Line = Struct.new(:text) do
        def print_to(output) = output.raw(text)
      end

      # A labelled value among the printed lines.
      Row = Struct.new(:label, :value) do
        def print_to(output) = output.row(label, value)
      end

      # A line for standard error: a note on what the call could not finish, beside what it did.
      Warning = Struct.new(:text) do
        def print_to(output) = output.warn(text)
      end

      def initialize
        @entries = []
      end

      def line(text) = @entries << Line.new(text)

      def row(label, value) = @entries << Row.new(label, value)

      def warning(text) = @entries << Warning.new(text)

      def lines = @entries.grep(Line).map(&:text)

      def print_to(output) = @entries.each { |entry| entry.print_to(output) }
    end
  end
end
