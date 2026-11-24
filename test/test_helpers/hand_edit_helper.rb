# frozen_string_literal: true

module Plastic
  class TestCase
    # Reads the refusal a printing call makes when a printed file was changed by hand.
    module HandEditHelper
      LINE = "%s changed since its last print on this home, by hand or in a copy from another home; run plastic store sync up first to read it into rows"

      def refusal(path) = format(LINE, path)

      def assert_refused(result, path)
        assert_equal [1, true, true], [result.code, result.err.include?(refusal(path)), result.out.include?("next: plastic store sync up")], result.err
      end
    end
  end
end
