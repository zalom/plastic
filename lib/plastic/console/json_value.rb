# frozen_string_literal: true

module Plastic
  module Console
    # A value of the console as JSON data: what JSON holds as it is stays as it
    # is, a hash gets text keys, and anything else prints as its inspect text.
    module JsonValue
      PLAIN = [String, Integer, true, false, nil].freeze

      module_function

      def of(value)
        case value
        when *PLAIN then value
        when Float then value.finite? ? value : value.inspect
        when Array, Hash then members(value)
        else value.inspect
        end
      end

      def members(value)
        return value.map { |item| of(item) } if value.is_a?(Array)

        value.to_h { |key, item| [key.to_s, of(item)] }
      end
    end
  end
end
