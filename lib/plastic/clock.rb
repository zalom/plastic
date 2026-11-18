# frozen_string_literal: true

require "time"

# The one way Plastic writes a time: local time with its offset. The time comes from
# the clock a caller was given, never from the machine here.
module Plastic
  def self.timestamp(time) = time.iso8601
end
