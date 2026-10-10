# frozen_string_literal: true

module CommandReference
  class Touches
    # The private methods of the graph classes that build one helper class, and
    # the calls on them that a piece of code makes.
    class Accessors
      CONSTANT = /([A-Z]\w*(?:::[A-Z]\w*)*)\.new/
      PATTERN = /^\s*def (\w+)\s*=.*?#{CONSTANT}|built\(:(\w+)\)\s*\{.*?#{CONSTANT}/

      def self.entry(row)
        found = row.match(PATTERN) or return
        [found[1] || found[3], found[2] || found[4]]
      end

      def self.methods_of(text, name) = text.scan(/(?<![\w.@:])(?<!def )#{Regexp.escape(name)}(?![\w:?!(])(?:\.(\w+[?!]?))?/).flatten.uniq

      def initialize(source, files)
        @source = source
        @files = files
      end

      def class?(klass) = table.value?(klass)

      def calls(text) = table.flat_map { |name, klass| pairs(text, name, klass) }

      private

      def pairs(text, name, klass) = self.class.methods_of(text, name).map { |method| [klass, method] }

      def table = @table ||= @files.flat_map { |file| rows(file) }.to_h

      def rows(file) = @source.lines(file).filter_map { |row| self.class.entry(row) }
    end
  end
end
