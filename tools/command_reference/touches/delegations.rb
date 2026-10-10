# frozen_string_literal: true

module CommandReference
  class Touches
    # The def_delegator and def_delegators lines of one graph file, as a table from method name to accessor.
    class Delegations
      SINGLE = /def_delegator\s+("?[:@\w.]+"?),\s*:(\w+[?!]?)(?:,\s*:(\w+[?!]?))?/
      PLURAL = /def_delegators\s+("?[:@\w.]+"?),\s*(.+)/
      NAME = /:(\w+[?!]?)/

      def initialize(source, file)
        @text = source.lines(file).join("\n").gsub(/,\s*\n\s*/, ", ")
      end

      def table = singles.merge(plurals)

      private

      def singles = @text.scan(SINGLE).to_h { |accessor, real, aliased| [aliased || real, [accessor, real]] }

      def plurals = @text.scan(PLURAL).flat_map { |accessor, names| names.scan(NAME).flatten.product([accessor]) }.to_h { |name, accessor| [name, [accessor, name]] }
    end
  end
end
