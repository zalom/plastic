# frozen_string_literal: true

module CommandReference
  module Figures
    # What one command touches, left to right: the command, its workflows, the classes behind them, the databases, the files.
    class Component
      COLUMNS = { command: 16, flows: 176, parts: 336, databases: 556, files: 766 }.freeze
      WIDTHS = { command: 140, flows: 140, parts: 196, databases: 186, files: 200 }.freeze

      def initialize(page)
        @page = page
        @touches = page.touches
      end

      def canvas
        drawing = Canvas.new(980, "What plastic #{@page.words} touches")
        heads(drawing)
        drawing.rect(COLUMNS[:command], 34, WIDTHS[:command], 40, "lane-code")
        drawing.text(COLUMNS[:command] + 10, 58, "plastic #{@page.words}", "tm")
        list(drawing, :flows, @page.flows.map { |flow| Words.short(flow.klass) }, "lane-#{@page.flows.first&.lane || "code"}")
        list(drawing, :parts, @touches.components.map(&:name), "card")
        databases(drawing)
        list(drawing, :files, @touches.files, "card")
        drawing
      end

      private

      def heads(drawing)
        { command: "COMMAND", flows: "WORKFLOWS", parts: "CLASSES", databases: "DATABASES", files: "FILES IT PRINTS" }.each do |column, title|
          drawing.text(COLUMNS[column], 20, title, "tag tag-muted")
        end
      end

      def list(drawing, column, names, css)
        names.each_with_index { |name, at| item(drawing, column, name, at, css) }
      end

      def item(drawing, column, name, at, css)
        top = 34 + at * 34
        drawing.rect(COLUMNS[column], top, WIDTHS[column], 28, css)
        drawing.text(COLUMNS[column] + 8, top + 18, name, "tm")
      end

      def databases(drawing)
        return drawing.text(COLUMNS[:databases], 58, "touches no database", "tm tag-muted") if @touches.entries.empty?

        @touches.database_files.reduce(34) { |top, file| database(drawing, file, top) + 14 }
      end

      def database(drawing, file, top)
        tables = @touches.tables_of(file)
        height = 30 + tables.size * 15
        drawing.rect(COLUMNS[:databases], top, WIDTHS[:databases], height, "db", rx: 14)
        drawing.text(COLUMNS[:databases] + 12, top + 18, file, "tb")
        tables.each_with_index { |table, at| drawing.text(COLUMNS[:databases] + 12, top + 34 + at * 15, "#{table}  #{marks(file, table)}", "tm") }
        wires(drawing, file, top + 14)
        top + height
      end

      def marks(file, table) = [(@touches.reads?(file, table) ? "R" : nil), (@touches.writes?(file, table) ? "W" : nil)].compact.join

      def wires(drawing, file, middle)
        edge = COLUMNS[:parts] + WIDTHS[:parts]
        drawing.wire([[edge + 4, middle - 3], [COLUMNS[:databases], middle - 3]]) unless @touches.tables_of(file, :write).empty?
        drawing.wire([[COLUMNS[:databases], middle + 5], [edge + 4, middle + 5]], "wire-read") unless @touches.tables_of(file, :read).empty?
      end
    end
  end
end
