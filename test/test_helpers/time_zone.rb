# frozen_string_literal: true

# Runs a block with the process in the zone `name`, the way a machine in that zone runs
# Plastic, and puts the zone the process had back after it.
module TimeZone
  def in_zone(name)
    was = ENV.fetch("TZ", nil)
    ENV["TZ"] = name
    yield
  ensure
    ENV["TZ"] = was
  end
end
