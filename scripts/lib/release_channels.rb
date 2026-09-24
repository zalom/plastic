# plastic-script-version: 1.0.0
#
# Turns a GitHub releases list into the newest version per channel. The
# GitHub releases API is the source of truth for intent 391's curl-based
# update path: no npm, no dist-tags. A release's tag_name carries the
# channel: "-alpha" or "-beta" in the tag marks a bleeding channel, anything
# else counts as stable and lands in the "latest" slot, matching the old
# npm dist-tag name so compute_target's channel logic stays unchanged. A
# draft release is skipped: it is not a real, installable release yet.

module ReleaseChannels
  module_function

  # Parse "MAJOR.MINOR.PATCH[-prerelease]" into a comparable structure.
  # Returns nil for anything that isn't a clean semver string.
  def parse(version)
    m = /\A(\d+)\.(\d+)\.(\d+)(?:-(.+))?\z/.match(version.to_s.strip)
    return nil unless m

    { maj: m[1].to_i, min: m[2].to_i, pat: m[3].to_i,
      pre: m[4] ? m[4].split(".") : nil }
  end

  # Semver precedence (§11). Returns -1, 0, or 1.
  def compare(a, b)
    %i[maj min pat].each do |k|
      return a[k] <=> b[k] unless a[k] == b[k]
    end
    return 0 if a[:pre].nil? && b[:pre].nil?
    return 1 if a[:pre].nil?
    return -1 if b[:pre].nil?

    [a[:pre].length, b[:pre].length].max.times do |i|
      x = a[:pre][i]
      y = b[:pre][i]
      return -1 if x.nil?
      return 1 if y.nil?

      xn = x.match?(/\A\d+\z/)
      yn = y.match?(/\A\d+\z/)
      if xn && yn
        return x.to_i <=> y.to_i unless x.to_i == y.to_i
      elsif xn
        return -1
      elsif yn
        return 1
      elsif x != y
        return x <=> y
      end
    end
    0
  end

  def channel(tag_name)
    version = tag_name.to_s.sub(/\Av/, "")
    return "alpha" if version.include?("-alpha")
    return "beta" if version.include?("-beta")

    "latest"
  end

  # releases: an array of GitHub release hashes, each with "tag_name" and
  # "draft" (string or symbol keys, either works). Returns a Hash of
  # channel name to the newest bare version string in that channel, e.g.
  # {"alpha" => "2.0.0-alpha.5", "latest" => "1.14.1"}. A channel with no
  # release is absent from the result, never nil.
  def channels(releases)
    best = {}
    best_parsed = {}

    Array(releases).each do |release|
      draft = release["draft"]
      draft = release[:draft] if draft.nil?
      next if draft

      tag_name = release["tag_name"] || release[:tag_name]
      next unless tag_name

      version = tag_name.to_s.sub(/\Av/, "")
      parsed = parse(version)
      next unless parsed

      ch = channel(tag_name)
      if best_parsed[ch].nil? || compare(parsed, best_parsed[ch]) > 0
        best[ch] = version
        best_parsed[ch] = parsed
      end
    end

    best
  end
end
