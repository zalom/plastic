# frozen_string_literal: true

module Plastic
  module Console
    # A value of the console as JSON data: what JSON holds as it is stays as it
    # is, a hash gets text keys, and anything else prints as its inspect text.
    module JsonValue
      module_function

      def of(value)
        case value
        when String, Integer, true, false, nil then value
        when Float then value.finite? ? value : value.inspect
        when Array then value.map { |item| of(item) }
        when Hash then value.to_h { |key, item| [key.to_s, of(item)] }
        else value.inspect
        end
      end
    end
  end
end
