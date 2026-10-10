# frozen_string_literal: true

module CommandReference
  class Touches
    # Reads the files a command runs and lists the graph calls in them, then
    # the tables each call reads or writes.
    class Scan
      CALL = /\b(work|retrieval)\.(\w+[?!]?)(?:\.(\w+[?!]?))?/
      WRITE = ->(table) { /put\(:#{table}\b|INTO "?#{table}\b|UPDATE "?#{table}\b|DELETE FROM "?#{table}\b|(?:write|insert)_rows\(:#{table}\b/ }
      KEYWORD = ->(table) { /(?<![\w.:])#{table}:(?!:)/ }
      ROWS = /\b(?:write|insert)_rows\b/
      MENTION = ->(table) { /(?<![.\w]):#{table}\b|"#{table}"|(?:FROM|JOIN)\s+"?#{table}\b/ }

      def initialize(source, facade, schema)
        @source = source
        @facade = facade
        @schema = schema
      end

      def call(files)
        targets = files.flat_map { |file| calls(file) }.flat_map { |side, method, hop| @facade.targets(side.to_sym, method, hop) }.uniq { |t| [t.file, t.text.hash] }
        Touches.new(entries: targets.flat_map { |target| entries(target) }, components: parts(targets), files: [], schema: @schema)
      end

      private

      def calls(file) = @source.lines(file).join("\n").scan(CALL).map { |side, method, hop| [side, method, hop] }

      def parts(targets) = targets.filter_map { |target| Part.new(target.component, target.file) if target.component }

      def entries(target)
        found = entries_of(target.text)
        found.empty? ? deeper(target) : found
      end

      def entries_of(text) = @schema.tables.filter_map { |table| entry(text, table) }

      def deeper(target)
        whole = @source.lines(target.file).join("\n")
        names = whole.scan(/\b([A-Z]\w*(?:::[A-Z]\w+)*)\.new\b/).flatten.uniq
        names.filter_map { |name| @facade.constant_file(name) }.uniq.flat_map { |file| entries_of(@source.lines(file).join("\n")) }
      end

      def entry(text, table)
        mode = mode_of(text, table)
        Entry.new(@schema.file_of(table), table, mode) if mode
      end

      def mode_of(text, table)
        return :write if text.match?(WRITE.call(table)) || (text.match?(ROWS) && text.match?(KEYWORD.call(table)))

        :read if text.match?(MENTION.call(table))
      end
    end
  end
end
