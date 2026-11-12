# frozen_string_literal: true

module CommandReference
  module Figures
    # What one call reads, writes and prints: the databases it reads on the left, the command in the middle, the databases it writes on the right, the files it prints below.
    class Touches
      READS = Box.new(16, 34, 220, 0)
      COMMAND = Box.new(290, 34, 220, 0)
      WRITES = Box.new(564, 34, 220, 0)
      WIDTH = 800
      GAP = 12

      def initialize(page)
        @page = page
        @touches = page.touches
        @drawing = Canvas.new(WIDTH, "What one call of plastic #{page.words} reads, writes and prints")
      end

      def canvas = @canvas ||= paint

      private

      def paint
        heads
        reading = stack(READS, :read)
        writing = stack(WRITES, :write)
        command([reading, writing].max)
        printed
        @drawing
      end

      def heads
        [[READS, "READS"], [COMMAND, "COMMAND"], [WRITES, "WRITES"]].each { |column, title| @drawing.text(Point.new(column.left, 20), title, "tag tag-muted") }
      end

      def stack(column, mode)
        files = @touches.database_files.select { |file| @touches.in?(file, mode) }
        files.reduce(column.top) { |top, file| database(column, file, mode, top) + GAP }.then { |bottom| [bottom - GAP, column.top].max }
      end

      def database(column, file, mode, top)
        labels = tables(file, mode)
        frame = Box.new(column.left, top, column.width, 30 + labels.size * 15)
        @drawing.rect(frame, "db", rx: 14)
        @drawing.text(frame.at(12, 18), file, "tb")
        @drawing.roomy(frame.at(12, 34), labels, "tm")
        wire(column, mode, top + 15)
        frame.bottom
      end

      def wire(column, mode, height)
        return @drawing.wire([Point.new(column.right + 2, height), Point.new(COMMAND.left - 2, height)], "wire-read") if mode == :read

        @drawing.wire([Point.new(COMMAND.right + 2, height), Point.new(column.left - 2, height)])
      end

      def tables(file, mode)
        found = @touches.tables_of(file, mode)
        found.empty? ? ["tables not found"] : found
      end

      def command(bottom)
        frame = Box.new(COMMAND.left, COMMAND.top, COMMAND.width, [bottom - COMMAND.top, 40].max)
        @drawing.rect(frame, "lane-code")
        @drawing.text(frame.at(10, 24), "plastic #{@page.words}", "tm")
        @drawing.text(frame.at(10, 44), "no database found in the code", "tm tag-muted") if @touches.database_files.empty?
      end

      def printed
        top = [@drawing.height, 80].max + 24
        @drawing.text(Point.new(READS.left, top), "PRINTED FILES", "tag tag-muted")
        names = @touches.files.empty? ? ["no store file"] : @touches.files
        names.each_with_index { |name, at| card(name, top + 8 + at * 34) }
      end

      def card(name, top)
        slot = Box.new(READS.left, top, WRITES.right - READS.left, 28)
        @drawing.rect(slot, "card")
        @drawing.text(slot.at(8, 18), name, "tm")
      end
    end
  end
end
