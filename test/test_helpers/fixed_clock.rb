# frozen_string_literal: true

# One moment every test that builds a writer, a reader or a graph by hand passes in, so a row carries the same time on every run.
module FixedClock
  AT = Time.utc(2026, 11, 17, 8, 0, 0)

  STAMP = AT.iso8601

  Clock = Struct.new(:now)

  CLOCK = Clock.new(AT)
end
