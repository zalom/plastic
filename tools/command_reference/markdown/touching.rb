# frozen_string_literal: true

module CommandReference
  module Markdown
    # What one call reads, writes and prints: the figure, a table of databases and files, and what a second call runs again.
    class Touching
      NOTHING = "It reads and writes no store database and prints no store file."
      UNDECLARED = "found in the code, not declared"

      def initialize(page, links)
        @page = page
        @links = links
        @touches = page.touches
      end

      def lines
        ["## What one call reads, writes and prints", "", "![What one call of plastic #{@page.words} reads, writes and prints](touches.svg)", "",
          *places, *SecondCall.new(@page, @links).lines]
      end

      private

      def places
        return [NOTHING, ""] if @touches.database_files.empty? && @touches.files.empty?

        ["| Place | Database or file | Tables | Reads or writes | Code |", "| --- | --- | --- | --- | --- |", *databases, *printed, ""]
      end

      def databases = @touches.database_files.map { |file| "| #{place(file)} | #{file} | #{tables(file)} | #{modes(file).join(" and ")} | #{declaration(file)} |" }

      def place(file) = (file == "local.db") ? "the home folder" : "the store folder"

      def tables(file) = @touches.tables_of(file).map { |table| "`#{table}`" }.join(", ").then { |text| text.empty? ? "not found in the code" : text }

      def modes(file) = { read: "reads", write: "writes" }.select { |mode, _| @touches.in?(file, mode) }.values

      def declaration(file)
        places = Touches::MODES.select { |mode| @touches.in?(file, mode) }.filter_map { |mode| @touches.declaration(file, mode) }.uniq
        places.empty? ? UNDECLARED : places.map { |found| @links.at(found) }.join(", ")
      end

      def printed = @touches.file_lines.map { |file, line| "| the store folder | #{file} | | writes | #{@links.code(Prints::FILE, line)} |" }
    end

    # What a second call does with each step: skip it when its done check holds, run it again when the check is false.
    class SecondCall
      def initialize(page, links)
        @steps = page.flows.flat_map { |flow| flow.rows.select { |row| %i[step agent].include?(row.kind) } }
        @links = links
      end

      def lines
        return [] if @steps.empty?

        ["A second call runs the same rows again. A step runs again only when its done check fails.", "",
          "| Step | Done when | The second call | Code |", "| --- | --- | --- | --- |", *@steps.map { |row| line(row) }, ""]
      end

      private

      def line(row) = "| #{Words.cell(row.name)} | #{row.check_cell} | #{(Array(row.check).join == "false") ? "runs it again" : "skips it"} | #{@links.code(row.file, row.line)} |"
    end
  end
end
