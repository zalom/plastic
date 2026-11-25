# frozen_string_literal: true

module Plastic
  # A wiring error: a routine or workflow is built wrong. Raised when the class
  # body loads or on the first call, never as a normal outcome of a call.
  Invalid = Class.new(StandardError)
end
