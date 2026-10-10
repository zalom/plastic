# frozen_string_literal: true

module CommandReference
  module Figures
    # One database file with its tables, each marked read or written, and the wires to the classes.
    class DatabaseBox
      def initialize(drawing, touches, file)
        @drawing = drawing
        @touches = touches
        @file = file
        @column = Component::COLUMNS.fetch(:databases)
      end

      def draw(top)
        frame = Box.new(@column.left, top, @column.width, 30 + labels.size * 15)
        @drawing.rect(frame, "db", rx: 14)
        caption(frame)
        wires(frame.top + 14)
        frame.bottom
      end

      private

      def labels = @labels ||= @touches.tables_of(@file).map { |table| "#{table}  #{marks(table)}" }

      def caption(frame)
        @drawing.text(frame.at(12, 18), @file, "tb")
        @drawing.roomy(frame.at(12, 34), labels, "tm")
      end

      def marks(table) = [(@touches.reads?(@file, table) ? "R" : nil), (@touches.writes?(@file, table) ? "W" : nil)].compact.join

      def wires(middle)
        near = Point.new(Component::COLUMNS.fetch(:parts).right + 4, middle)
        far = Point.new(@column.left, middle)
        @drawing.wire([near.shift(0, -3), far.shift(0, -3)]) unless @touches.tables_of(@file, :write).empty?
        @drawing.wire([far.shift(0, 5), near.shift(0, 5)], "wire-read") unless @touches.tables_of(@file, :read).empty?
      end
    end
  end
end
