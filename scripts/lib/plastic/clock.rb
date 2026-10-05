# frozen_string_literal: true

require "time"

# The one source of the time Plastic writes: local time with its offset.
module Plastic
  def self.now = Time.now.iso8601
end
