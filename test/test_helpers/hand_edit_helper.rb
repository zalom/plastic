# frozen_string_literal: true

module Plastic
  class TestCase
    # Reads the refusal a printing call makes when a printed file was changed by hand.
    module HandEditHelper
      LINE = "%s changed by hand since the last print; run plastic sync up first"

      def refusal(path) = format(LINE, path)

      def assert_refused(result, path)
        assert_equal [1, true, true], [result.code, result.err.include?(refusal(path)), result.out.include?("next: plastic sync up")], result.err
      end
    end
  end
end
