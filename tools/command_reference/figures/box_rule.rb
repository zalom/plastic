# frozen_string_literal: true

module CommandReference
  module Figures
    # The rule for the words in a box: plain English, no class path, method name or file name.
    module BoxRule
      CODE = /::|\b[a-z]+_[a-z_]+\b|\.rb\b|\(\)/

      def self.code?(words) = words.to_s.match?(CODE)
    end
  end
end
