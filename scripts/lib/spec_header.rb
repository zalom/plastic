# encoding: UTF-8
# frozen_string_literal: true

# SpecHeader - the single implementation that parses the `Tier:` and `Settled:` lines out
# of a spec.md's header block (intent 213). No script, skill, or hook re-implements this
# grammar anywhere else; Bridge.savepoint_tier delegates here instead of carrying its own
# copy of the Tier regex.
#
# Grammar (both lines live above the `# ` level-1 heading):
#
#   Tier: L
#   Settled: yes (design fixed by the 2026-07-18 Fable advisor verdict)
#
# `Tier:` is exactly one of S, M, L; anything else is unparseable and yields nil. An ABSENT
# `Settled:` line means not settled, there is no `Settled: no` variant.
module SpecHeader
  module_function

  # Mirrors Bridge::PLACEHOLDER_SENTINEL (scripts/lib/bridge.rb:22). Not required in from
  # bridge.rb to avoid a require cycle: bridge.rb requires spec_header.rb, so spec_header.rb
  # must have zero require_relative dependencies of its own.
  PLACEHOLDER_SENTINEL = "<!-- plastic:placeholder -->"

  HEADER_BLOCK_MAX_LINES = 10

  TIER_RE = /\ATier:\s*(S|M|L)\z/
  SETTLED_RE = /\ASettled:\s*yes\s*(?:\((.*)\))?\z/

  # PURE. Parse a spec.md's raw text. Returns a Hash with symbol keys, always the same
  # three keys: tier ("S"|"M"|"L"|nil), settled (true|false), settled_reason (String|nil).
  def parse(text)
    result = { tier: nil, settled: false, settled_reason: nil }
    return result if text.nil?

    lines = text.each_line.first(HEADER_BLOCK_MAX_LINES)
    lines.each do |raw|
      line = raw.chomp.strip
      next if line.empty?
      next if line == PLACEHOLDER_SENTINEL
      break if line.start_with?("# ")

      if (m = line.match(TIER_RE))
        result[:tier] = m[1]
      elsif (m = line.match(SETTLED_RE))
        result[:settled] = true
        result[:settled_reason] = m[1]
      end
    end

    result
  end

  # Read at most the header block off disk and parse it. Returns the same Hash shape as
  # `parse`, with every value nil/false when the path does not exist or cannot be read.
  def parse_file(path)
    lines = []
    File.open(path) do |f|
      HEADER_BLOCK_MAX_LINES.times do
        line = f.gets
        break if line.nil?
        lines << line
      end
    end
    parse(lines.join)
  rescue StandardError
    { tier: nil, settled: false, settled_reason: nil }
  end

  # Render the two header lines for a spec.md. `tier` is "S"|"M"|"L" or nil, `settled_reason`
  # is a String or nil. Returns a String ending in one newline. A nil tier renders the
  # placeholder `Tier: S|M|L`; a nil reason renders no Settled line at all (absent means not
  # settled).
  def render(tier: nil, settled_reason: nil)
    lines = []
    lines << "Tier: #{tier || 'S|M|L'}"
    lines << "Settled: yes (#{settled_reason})" if settled_reason
    "#{lines.join("\n")}\n"
  end
end
