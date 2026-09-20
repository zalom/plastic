# encoding: UTF-8
# frozen_string_literal: true

# VersionNumber - dotted version comparison without RubyGems (intent 363).
#
# The launcher starts as `ruby --disable-gems`, which saves about 26 of the 40
# milliseconds a plain Ruby process costs, so no file a command loads may reach
# for Gem::Version. Parses the leading run of dotted integers, ignoring a
# leading "v" and anything after the digits, and compares two of them segment by
# segment with the shorter one zero-padded. A string with no leading integer
# parses to nil, so a caller answers "not found" instead of raising.
#
# It deliberately does not order pre-release suffixes: 2.0.0-alpha.27 and 2.0.0
# compare equal here. A caller that needs RubyGems' pre-release order, such as
# the release-tag reader in scripts/report-screen, keeps Gem::Version.
class VersionNumber
  include Comparable

  LEADING_DIGITS = /\A(\d+(?:\.\d+)*)/

  attr_reader :segments

  def self.parse(value)
    match = LEADING_DIGITS.match(value.to_s.strip.sub(/\Av/, ""))
    match && new(match[1].split(".").map(&:to_i))
  end

  def initialize(segments)
    @segments = segments
  end

  def <=>(other)
    return nil unless other.is_a?(VersionNumber)

    width = [segments.length, other.segments.length].max
    padded(width) <=> other.padded(width)
  end

  def to_s
    segments.join(".")
  end

  protected

  def padded(width)
    segments + Array.new(width - segments.length, 0)
  end
end
