# frozen_string_literal: true

require "json"
require_relative "../../invalid"

module Plastic
  module Graph
    module SQL
      # How a Ruby value becomes a value SQLite binds.
      module Binding
        LARGEST_INTEGER = 2**63 - 1

        module_function

        def bindable(value)
          convert(value)
        rescue => error
          raise Plastic::Invalid, "a #{value.class} cannot be bound: #{error.message}"
        end

        def convert(value)
          case value
          in nil | Float | SQLite3::Blob then value
          in true then 1
          in false then 0
          in Integer then integer(value)
          in Hash | Array then JSON.generate(value)
          in String then text(value)
          else value.to_s
          end
        end

        def integer(value)
          raise RangeError, "out of range" unless value.abs <= LARGEST_INTEGER

          value
        end

        def text(value) = (value.encoding == Encoding::BINARY) ? value.dup.force_encoding(Encoding::UTF_8) : value
      end
    end
  end
end
