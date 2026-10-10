# frozen_string_literal: true

module CommandReference
  module Figures
    # What one command touches, left to right: the command, its workflows, the classes behind them, the databases, the files.
    class Component
      # One column of the drawing: where it starts, how wide it is and how its boxes look.
      Column = Data.define(:left, :width, :css) do
        def right = left + width

        def frame(height) = Box.new(left, 34, width, height)

        def slot(at) = Box.new(left, 34 + at * 34, width, 28)
      end
      COLUMNS = {
        command: Column.new(16, 140, "lane-code"), flows: Column.new(176, 140, "lane-code"), parts: Column.new(336, 196, "card"),
        databases: Column.new(556, 186, "db"), files: Column.new(766, 200, "card")
      }.freeze
      LEGEND = ["R read  W write", "declared: named by the", "command, tables not found"].freeze
      TITLES = { command: "COMMAND", flows: "WORKFLOWS", parts: "CLASSES", databases: "DATABASES", files: "FILES IT PRINTS" }.freeze

      def initialize(page)
        @page = page
        @flows = page.flows
        @touches = page.touches
        @drawing = Canvas.new(980, "What plastic #{page.words} touches")
      end

      def canvas = @canvas ||= paint

      private

      def paint
        header
        lists
        databases
        list(COLUMNS.fetch(:files), @touches.files)
        @drawing
      end

      def lists
        list(COLUMNS.fetch(:flows).with(css: "lane-#{@flows.first&.lane || "code"}"), @flows.map(&:short))
        list(COLUMNS.fetch(:parts), @touches.components.map(&:name))
      end

      def header
        heads
        command
      end

      def heads
        COLUMNS.each { |name, column| @drawing.text(Point.new(column.left, 20), TITLES.fetch(name), "tag tag-muted") }
      end

      def command
        column = COLUMNS.fetch(:command)
        frame = column.frame(40)
        @drawing.rect(frame, column.css)
        @drawing.text(frame.at(10, 24), "plastic #{@page.words}", "tm")
      end

      def list(column, names)
        names.each_with_index do |name, at|
          slot = column.slot(at)
          @drawing.rect(slot, column.css)
          @drawing.text(slot.at(8, 18), name, "tm")
        end
      end

      def databases
        return @drawing.text(Point.new(left, 58), "no database found in the code", "tm tag-muted") if @touches.database_files.empty?

        bottom = @touches.database_files.reduce(34) { |top, file| DatabaseBox.new(@drawing, @touches, file).draw(top) + 14 }
        legend(bottom + 12)
      end

      def legend(top)
        @drawing.paragraph(Point.new(left, top), LEGEND, "tm tag-muted")
        @drawing.grow(top + (LEGEND.size * 14))
      end

      def left = COLUMNS.fetch(:databases).left
    end
  end
end
