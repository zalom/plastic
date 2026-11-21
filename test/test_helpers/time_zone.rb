# frozen_string_literal: true

# Runs a block with the process in the zone `name`, the way a machine in that zone runs
# Plastic, and puts the zone the process had back after it. A test class that defines
# `machine_zone` runs each of its tests in that zone.
module TimeZone
  def in_zone(name)
    was = ENV.fetch("TZ", nil)
    ENV["TZ"] = name
    yield
  ensure
    ENV["TZ"] = was
  end

  def before_setup
    super
    return unless respond_to?(:machine_zone)

    @zone_was = ENV.fetch("TZ", nil)
    ENV["TZ"] = machine_zone
  end

  def after_teardown
    ENV["TZ"] = @zone_was if respond_to?(:machine_zone)
    super
  end
end
