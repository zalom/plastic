# frozen_string_literal: true

module CommandReference
  # The line that declares each store a command reads or writes: its own file, its parents and the modules it extends.
  class Declarations
    LINE = /\b(reads|writes)\s+((?::\w+(?:,\s*)?)+)\s*\z/
    MODES = { "reads" => :read, "writes" => :write }.freeze
    OWNERS = [Plastic::Routine, Plastic::CLI::Command, Plastic::Hook].freeze

    def initialize(source, klass)
      @source = source
      @klass = klass
    end

    # [mode, store key] to the Place of the line that declares it.
    def to_h = files.flat_map { |file| in_file(file) }.reverse.to_h

    private

    def files = holders.filter_map { |holder| path_of(holder) }.uniq

    def holders = [*@klass.ancestors.grep(Class).take_while { |each| !OWNERS.include?(each) }, *@klass.singleton_class.included_modules]

    def path_of(holder)
      found = Object.const_source_location(holder.name)&.first if holder.name
      @source.relative(found) if found&.start_with?(@source.root)
    end

    def in_file(file)
      @source.lines(file).each_with_index.flat_map do |text, at|
        match = text.match(LINE)
        match ? match[2].scan(/:(\w+)/).flatten.map { |key| [[MODES.fetch(match[1]), key.to_sym], Place.new(file, at + 1, text.strip)] } : []
      end
    end
  end
end
