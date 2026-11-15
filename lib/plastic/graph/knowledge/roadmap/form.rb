# frozen_string_literal: true

require_relative "../../../invalid"

module Plastic
  module Graph
    module Knowledge
      class Roadmap
        # The print form of a roadmap file: a form line first, then one labeled line for each value.
        # A newline in a value prints as \n and a backslash as \\, so a value never starts a line of its own.
        module Form
          LINE = "<!-- plastic roadmap form 2 -->"
          LABELED = /\A\s*([a-z_]+):(?: (.*))?\z/
          ESCAPES = { "n" => "\n", "\\" => "\\" }.freeze

          module_function

          def form?(text) = text.lines.first.to_s.chomp == LINE

          def escape(value) = value.to_s.gsub(/[\\\n]/) { |char| (char == "\n") ? "\\n" : "\\\\" }

          def unescape(value)
            value.gsub(/\\(.)?/m) { ESCAPES.fetch(Regexp.last_match(1)) { raise Invalid, "a value holds a backslash that is not \\n or \\\\" } }
          end

          def labeled(key, value) = "#{key}: #{escape(value)}".rstrip
        end
      end
    end
  end
end
