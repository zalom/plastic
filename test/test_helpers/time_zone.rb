# frozen_string_literal: true

# How a stored time shows on the machine that runs the suite: in the zone of the machine, with its offset.
# A test that needs another zone passes its offset as a value, or starts a child process with TZ.
module TimeZone
  def shown(stamp) = Time.iso8601(stamp).getlocal.iso8601
end
