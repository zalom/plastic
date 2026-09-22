# encoding: UTF-8
# frozen_string_literal: true

# NodeInputCompatibility (intent 338a, G6, n1, D10/D11): the one seam that
# lets a `running` line written before the node-input rename keep reading
# correctly. It is the ONLY shipped file allowed to name the retired field,
# and it names it exactly once, as LEGACY_FIELD below.
#
# It maps, never rewrites: the raw ledger line on disk is never touched.
# `NodeLedger.parse_transition_line` calls #fields on every parsed field hash
# before returning it, so torn detection, attempt counting, node-run,
# graph-measure and outcome-report all see `input` whether the line was
# written by an old dispatch or a new one.
#
# No project requires (spec D10): a plain module over a plain hash, so
# `node_ledger.rb` never gains a require cycle through this file.
module NodeInputCompatibility
  module_function

  # The retired field name, named once. No other shipped file names it.
  LEGACY_FIELD = "packet"

  # The retired directory and suffix (338a n3, D8), named once beside
  # LEGACY_FIELD. No other shipped file spells either literal; a caller
  # that needs the legacy input location builds it from these constants.
  LEGACY_DIRECTORY = "packets"
  LEGACY_SUFFIX = ".packet"

  # A copy of `fields` where LEGACY_FIELD maps to "input" when "input" is
  # absent or blank. "input" wins when both are present (D11): the newer,
  # authoritative name is never overwritten by the retired one. LEGACY_FIELD
  # itself is dropped from the copy either way, so a caller that renders
  # every field it does not recognize (outcome-report's evidence line) never
  # sees the retired key leak through as a second, unrecognized field.
  def fields(fields)
    source = fields || {}
    return source.dup unless source.key?(LEGACY_FIELD)

    mapped = source.dup
    unless present?(mapped["input"])
      mapped["input"] = mapped[LEGACY_FIELD]
    end
    mapped.delete(LEGACY_FIELD)
    mapped
  end

  # 338a n3 (D8): the new path when it exists, the legacy directory and
  # suffix when only that file exists, and the new path when neither does
  # (a fresh attempt names its own soon-to-be-written destination).
  def input_path(intent_dir:, node:, attempt:)
    new_path = File.join(intent_dir, "attempts", "#{node}--a#{attempt}.input")
    return new_path if File.exist?(new_path)

    legacy_path = File.join(intent_dir, LEGACY_DIRECTORY, "#{node}--a#{attempt}#{LEGACY_SUFFIX}")
    File.exist?(legacy_path) ? legacy_path : new_path
  end

  def present?(value)
    !(value.nil? || value.to_s.strip.empty?)
  end
  private_class_method :present?
end
