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

      def of(name)
        line = @source.find_line(@file, /^\s*#{Regexp.escape(name)}\s*=/) or return
        rows = @source.lines(@file).drop(line - 1)
        tag = rows.first[HEREDOC, 2]
        (tag ? heredoc(rows, tag) : continued(rows)).join("\n")
      end

      private

      def heredoc(rows, tag) = rows.take((rows.index { |row| row.strip == tag } || 0) + 1)

      def continued(rows) = rows.slice_after { |row| !row.match?(CONTINUES) }.first
    end
  end
end
