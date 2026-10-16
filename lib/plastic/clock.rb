# frozen_string_literal: true

require "time"

# The one source of the time Plastic writes: local time with its offset.
module Plastic
  def self.now(time = Time.now) = time.iso8601
end
