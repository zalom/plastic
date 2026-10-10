# frozen_string_literal: true

module CommandReference
  class Touches
    # Reads the files a command runs and lists the graph calls in them, then
    # the tables each call reads or writes. A call leads to the code that runs
    # it, and that code to more calls, a few hops deep.
    class Scan
      CALL = /\b(work|retrieval)\.(\w+[?!]?)(?:\.(\w+[?!]?))?/
      QUOTE = '\\\\?"?'
      WRITE = ->(table) { /put\(:#{table}\b|INTO #{QUOTE}#{table}\b|UPDATE #{QUOTE}#{table}\b|DELETE FROM #{QUOTE}#{table}\b|(?:write|insert)_rows\(:#{table}\b/ }
      KEYWORD = ->(table) { /(?<![\w.:])#{table}:(?!:)/ }
      ROWS = /\b(?:write|insert)_rows\b/
      MENTION = ->(table) { /(?<![.\w]):#{table}\b|\\?"#{table}\\?"|(?:FROM|JOIN)\s+#{QUOTE}#{table}\b/ }
      HOPS = 3

      def initialize(source, facade, schema)
        @source = source
        @facade = facade
        @schema = schema
        @helpers = Helpers.new(source)
      end

      def call(files)
        targets = reached(files)
        Touches.new(entries: targets.flat_map { |target| entries_of(target.text) }, components: targets.filter_map(&:part), files: [], schema: @schema)
      end

      def self.mode_of(text, table)
        return :write if text.match?(WRITE.call(table)) || (text.match?(ROWS) && text.match?(KEYWORD.call(table)))

        :read if text.match?(MENTION.call(table))
      end

      private

      def reached(files)
        found = (files.flat_map { |file| from_text(@source.lines(file).join("\n")) } + @helpers.call(files)).uniq(&:key)
        frontier = found
        HOPS.times { found += (frontier = widen(frontier, found)) }
        found
      end

      def widen(frontier, found)
        known = found.to_set(&:key)
        frontier.flat_map { |target| onward(target) }.uniq(&:key).reject { |target| known.include?(target.key) }
      end

      def onward(target) = from_text(target.text) + @facade.follow(target)

      def from_text(text) = text.scan(CALL).flat_map { |side, method, hop| @facade.targets(side.to_sym, method, hop) }

      def entries_of(text) = @schema.tables.filter_map { |table| entry(text, table) }

      def entry(text, table)
        mode = Scan.mode_of(text, table)
        Entry.new(@schema.file_of(table), table, mode) if mode
      end
    end
  end
end
