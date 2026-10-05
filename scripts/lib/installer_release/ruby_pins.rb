# frozen_string_literal: true

module InstallerRelease
  # The Ruby builds install.sh pins, one per platform, read from its
  # ruby_pins table so the manifest of a release carries the same pins.
  module RubyPins
    FIELDS = %w[key version size sha256 root url].freeze
    SHIPPED = File.expand_path("../../../install.sh", __dir__)

    def self.read(script = File.read(SHIPPED))
      table = script[/^ruby_pins='\n(.*?)^'/m, 1] or raise VerificationError, "install.sh has no ruby_pins table"
      table.lines.to_h { |line| pin(*line.split) }
    end

    def self.pin(platform, *values)
      fields = FIELDS.zip(values).to_h
      [platform, fields.merge("size" => Integer(fields.fetch("size")))]
    end
  end
end
