# frozen_string_literal: true

module CommandReference
  class Touches
    # The text of a constant one file defines: a one-line value, a value that
    # continues onto the next lines, or a heredoc through its terminator.
    class ConstantText
      HEREDOC = /<<[~-]?(['"]?)(\w+)\1/
      CONTINUES = /(?:\\|,|\+|\(|\[|\{|\|\|)\s*\z/

      def initialize(source, file)
        @source = source
        @file = file
      end

      def self.text(rows)
        tag = rows.first[HEREDOC, 2]
        (tag ? rows.take(rows.index { |row| row.strip == tag }.to_i + 1) : rows.slice_after { |row| !row.match?(CONTINUES) }.first).join("\n")
      end

      def of(name) = (rows = rows_from(name)) && self.class.text(rows)

      private

      def rows_from(name)
        line = @source.find_line(@file, /^\s*#{Regexp.escape(name)}\s*=/)
        @source.lines(@file).drop(line - 1) if line
      end
    end
  end
end
