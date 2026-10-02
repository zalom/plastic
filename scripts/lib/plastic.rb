# frozen_string_literal: true

require "time"

# The root of the kernel. Every other file sits in a folder named after its
# namespace, under plastic/.
module Plastic
  def self.now = Time.now.iso8601

  # A class name in snake case: HandedOff is handed_off.
  def self.snake(name) = name.gsub(/(?<=[a-z0-9])(?=[A-Z])/, "_").downcase
end

require_relative "plastic/cli"
require_relative "plastic/routine"
require_relative "plastic/code_workflow"
require_relative "plastic/agent_workflow"
require_relative "plastic/architecture/enola_adapter"
require_relative "plastic/hook"
