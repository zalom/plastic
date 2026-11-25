# frozen_string_literal: true

require "time"
require_relative "invalid"

# The one way Plastic writes a time: UTC, in ISO 8601 with Z. The time comes from
# the clock a caller was given, never from the machine here. A time is shown in
# the zone of the machine only where a person reads it. Docs:
# docs/contributing/ARCHITECTURE.md.
module Plastic
  # A stored time: UTC with Z, or an offset as earlier releases wrote it.
  STAMP = /\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?(?:Z|[+-]\d\d:\d\d)\z/
  # The name of a field that holds a time: at, or a name that ends in _at.
  TIME_FIELD = /\A(?:\w+_)?at\z/

  def self.timestamp(time) = time.getutc.iso8601

  # The stored time in `zone`, an offset such as +09:00, or else in the zone of the machine; a date, a blank or other text shows as it is.
  def self.local(stamp, zone = nil)
    return stamp unless STAMP.match?(stamp.to_s)

    Time.new(stamp).getlocal(zone).iso8601
  rescue ArgumentError
    stamp
  end

  # The calendar day in `zone`, or else in the zone of the machine, on which the stored time falls; a blank or other text has no day.
  def self.local_day(stamp, zone = nil)
    Time.new(stamp).getlocal(zone).strftime("%F") if STAMP.match?(stamp.to_s)
  end

  # A time read from a file, in UTC; a date, a blank or other text reads as it is, and an impossible time is refused.
  def self.utc(stamp)
    return stamp unless STAMP.match?(stamp.to_s)

    timestamp(Time.new(stamp))
  rescue ArgumentError
    raise Invalid, "#{stamp} is not a time"
  end

  # The fields read from a file, with each time field in UTC.
  def self.utc_fields(fields) = fields.to_h { |key, value| [key, TIME_FIELD.match?(key) ? utc(value) : value] }
end
