# frozen_string_literal: true

module CommandReference
  class Touches
    # The classes of the Plastic code that a command's files name: a helper a
    # workflow or a command builds or calls. Each one is a part of the command
    # and is read as a whole file.
    class Helpers
      NAME = /\b[A-Z]\w*(?:::[A-Z]\w*)*/
      PREFIX = /\A(?:Plastic::)(?:Graph::)?/
      BASES = [Exception, Plastic::Workflow, Plastic::CLI::Command, Plastic::Hook].freeze
      PREFIXES = ["", "Workflows::"].freeze
      HELPER = ->(found) { found.is_a?(Class) && found.name.start_with?("Plastic::") && BASES.none? { |base| found <= base } }

      def self.klass(name)
        PREFIXES.each do |prefix|
          found = Plastic.const_get("#{prefix}#{name}")
          return found if HELPER.call(found)
        rescue NameError, LoadError
          next
        end
        nil
      end

      def initialize(source)
        @source = source
      end

      def call(files)
        own = files.to_set
        files.flat_map { |file| names(file) }.uniq.filter_map { |name| self.class.klass(name) }.uniq.filter_map { |klass| target(klass, own) }.uniq(&:part)
      end

      private

      def names(file) = @source.lines(file).reject { |row| row.lstrip.start_with?("#") }.join("\n").scan(NAME)

      def target(klass, own)
        name = klass.name
        file = @source.relative(Object.const_source_location(name).first)
        Target.new(@source, file, nil, name.sub(PREFIX, "")) unless own.include?(file)
      end
    end
  end
end
