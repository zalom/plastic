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
      method = @klass.instance_method(name)
      read(method) unless OWNERS.include?(method.owner)
    end

    private

    def name = (@klass <= Plastic::Hook) ? :respond : :call

    def read(method)
      home, line = place(method)
      OwnCall.new(home, line, @source.method_lines(home, line), check(method), reachable(home))
    end

    def check(call_method)
      return unless @klass.private_method_defined?(:check_call)

      method = @klass.instance_method(:check_call)
      return if method.owner == call_method.owner

      home, line = place(method)
      Place.new(home, line, @source.method_lines(home, line))
    end

    def reachable(home)
      own = @source.relative(Object.const_source_location(@klass.name).first)
      CallClosure.new(@source, [own, home].uniq, [name.to_s, "check_call"]).lines(home) unless home == own
    end

    def place(method)
      path, line = method.source_location
      [@source.relative(path), line]
    end
  end
end
