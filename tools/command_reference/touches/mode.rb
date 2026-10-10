# frozen_string_literal: true

module CommandReference
  class Touches
    # Whether a piece of code reads or writes one table, from the words it uses for it.
    class Mode
      QUOTE = '\\\\?"?'
      WRITE = ->(table) { /put\(:#{table}\b|INTO #{QUOTE}#{table}\b|UPDATE #{QUOTE}#{table}\b|DELETE FROM #{QUOTE}#{table}\b|(?:write|insert)_rows\(:#{table}\b/ }
      KEYWORD = ->(table) { /(?<![\w.:])#{table}:(?!:)/ }
      ROWS = /\b(?:write|insert)_rows\b/
      MENTION = ->(table) { /(?<![.\w]):#{table}\b|\\?"#{table}\\?"|(?:FROM|JOIN)\s+#{QUOTE}#{table}\b/ }

      def self.of(text, table)
        return :write if text.match?(WRITE.call(table)) || (text.match?(ROWS) && text.match?(KEYWORD.call(table)))

        :read if text.match?(MENTION.call(table))
      end
    end
  end
end
