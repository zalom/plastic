# frozen_string_literal: true

module CommandReference
  # Reads the call method a command writes for itself, when it writes one.
  class OwnCallReading
    OWNERS = [Plastic::Routine, Plastic::CLI::Command, Plastic::Hook].freeze

    def initialize(source, klass)
      @source = source
      @klass = klass
    end

    def call
      method = @klass.instance_method((@klass <= Plastic::Hook) ? :respond : :call)
      read(method) unless OWNERS.include?(method.owner)
    end

    private

    def read(method)
      path, line = method.source_location
      home = @source.relative(path)
      OwnCall.new(home, line, @source.method_lines(home, line))
    end
  end
end
