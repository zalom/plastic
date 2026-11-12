# frozen_string_literal: true

require_relative "plastic/clock"

# The root of the kernel. Every other file sits in a folder named after its
# namespace, under plastic/.
module Plastic
  # A class name in snake case: HandedOff is handed_off.
  def self.snake(name) = name.gsub(/(?<=[a-z0-9])(?=[A-Z])/, "_").downcase
end

require_relative "plastic/cli"
