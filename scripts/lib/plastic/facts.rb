# frozen_string_literal: true

require_relative "invalid"

module Plastic
  # The named values of one call. Only declared names exist, so a typo
  # raises instead of reading as nil.
  class Facts
    # A %{name} in a printed line.
    PLACEHOLDER = /%\{(\w+)\}/

    # The fact names a template prints, in order.
    def self.names_in(template) = template.scan(PLACEHOLDER).flatten.map(&:to_sym)

    attr_reader :declared

    def initialize(declared, values)
      @declared = declared.to_set
      @values = values.slice(*@declared)
    end

    def [](name) = @values[name]

    def []=(name, value)
      raise Invalid, "fact #{name} is not declared" unless @declared.include?(name)

      @values[name] = value
    end

    def to_h = @values.dup

    # Fills %{name} from the facts. A name with no value raises, so a
    # printed command never carries a hole.
    def fill(template)
      names = Facts.names_in(template)
      present = @values.slice(*names).compact
      missing = names - present.keys
      raise Invalid, "no value for #{missing.join(", ")} in #{template.inspect}" if missing.any?

      format(template, **present)
    end
  end
end
