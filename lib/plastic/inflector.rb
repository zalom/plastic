# frozen_string_literal: true

module Plastic
  # The words of a constant name, written the way their files are named.
  module Inflector
    # A class name in snake case: HandedOff is handed_off.
    def self.underscore(name) = name.gsub(/(?<=[a-z0-9])(?=[A-Z])/, "_").downcase
  end
end
