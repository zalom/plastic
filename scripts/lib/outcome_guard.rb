# encoding: UTF-8
# frozen_string_literal: true

require_relative "bridge"
require_relative "intent_validator"

# OutcomeGuard - the single definition of "is outcome.md real and disposition-matched for
# THIS close" (intent 222). Extracted verbatim from scripts/end-intent's own
# outcome_guard_reason (intent 161/188) so end-intent's existing exit-2 path and doctor's new
# per-intent check (intent_lifecycle_artifacts) can never independently drift on what counts
# as a valid outcome.md. Pure, read-only: authors nothing regardless of outcome.
module OutcomeGuard
  module_function

  DISPOSITIONS = %w[delivered abandoned].freeze

  # Returns nil when the guard PASSES, or a reason String to refuse with. Refuses a missing
  # file, a still-placeholder file (first line is the sentinel), or a disposition that does
  # not exactly equal the requested one.
  def reason(intent_dir, disposition)
    path = File.join(intent_dir, "outcome.md")
    return "outcome.md is missing at #{path}" unless File.exist?(path)

    content = File.read(path)
    first_line = content.each_line.first.to_s.chomp
    if first_line == Bridge::PLACEHOLDER_SENTINEL
      return "outcome.md is still the scaffold placeholder (first line is the sentinel)"
    end

    fm = IntentValidator.parse_frontmatter_text(content)
    actual = fm.is_a?(Hash) ? fm["disposition"] : nil
    unless DISPOSITIONS.include?(actual) && actual == disposition
      return "outcome.md frontmatter disposition is #{actual.inspect}, expected #{disposition.inspect}"
    end

    nil
  end
end
