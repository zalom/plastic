# frozen_string_literal: true

require "time"

# The one way Plastic writes a time: UTC, in ISO 8601 with Z. The time comes from
# the clock a caller was given, never from the machine here. A time is shown in
# the zone of the machine only where a person reads it. Docs:
# docs/contributing/ARCHITECTURE.md.
module Plastic
  # A stored time: UTC with Z, or an offset as earlier releases wrote it.
  STAMP = /\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?(?:Z|[+-]\d\d:\d\d)\z/

  def self.timestamp(time) = time.getutc.iso8601

  # The stored time in the zone of the machine with its offset; a date, a blank or other text shows as it is.
  def self.local(stamp)
    return stamp unless STAMP.match?(stamp.to_s)

    Time.iso8601(stamp).getlocal.iso8601
  rescue ArgumentError
    stamp
  end

  # The calendar day of the machine on which the stored time falls; a blank or other text has no day.
  def self.local_day(stamp) = STAMP.match?(stamp.to_s) ? Time.iso8601(stamp).getlocal.strftime("%F") : nil
end
