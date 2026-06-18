# encoding: UTF-8
# frozen_string_literal: true

require "yaml"
require "date"
require "time"

# IntentValidator — the single source of truth for "is an intent born complete?"
# (intent 60).
#
# An intent is born complete when its frontmatter carries every required field
# and its `sources` and `chain` are well-formed arrays of Folgezettel id references
# (bare ids like `1a2`, or cross-store refs like `global:1a2`; integer ids are coerced).
# This module is the only definition of that contract; the `validate-intent` CLI,
# the doctor diagnostics, and the creating-intent skill all consult it so the
# definition never drifts across copies.
#
# Pure and dependency-injected: `validate` accepts an injectable `plastic_home`
# for house-style parity, parses with a rescue-to-safe-default reader, uses no
# `eval`, and performs no file writes and no global-constant injection.
module IntentValidator
  module_function

  # Must match Doctor::REQUIRED_FRONTMATTER_FIELDS (scripts/doctor.rb).
  REQUIRED_FIELDS = %w[id intent sources chain created author tags].freeze

  # Fields whose value must be a well-formed array of valid id strings.
  ARRAY_ID_FIELDS = %w[sources chain].freeze

  # Folgezettel id form: digits then an optional lowercase-letter/digit suffix
  # (for example "14", "14a", "4a1"). Mirrors scripts/folgezettel-id.
  ID_PATTERN = /\A([a-z0-9-]+:)?\d+[a-z0-9]*\z/

  # True iff `value` is a String matching the Folgezettel id form.
  def valid_id?(value)
    value.to_s.match?(ID_PATTERN)
  end

  # Read a file's YAML frontmatter, returning the parsed Hash (or {} when the
  # frontmatter block is empty), or nil when there is no parseable frontmatter.
  # A copy of Doctor#parse_frontmatter so `created:` dates do not crash.
  def parse_frontmatter(path)
    return nil unless File.exist?(path)

    content = File.read(path)
    return nil unless content.start_with?("---")

    parts = content.split("---", 3)
    return nil if parts.length < 3

    YAML.safe_load(parts[1], permitted_classes: [Date, Time]) || {}
  rescue StandardError
    nil
  end

  # PURE: given a parsed frontmatter Hash (or nil), return
  # { ok: Boolean, missing: [field names], errors: [human strings] }.
  def validate_frontmatter(fm)
    unless fm.is_a?(Hash)
      return { ok: false, missing: REQUIRED_FIELDS.dup, errors: ["no frontmatter found"] }
    end

    missing = REQUIRED_FIELDS.reject { |f| fm.key?(f) }
    errors = missing.map { |f| "missing required field: #{f}" }

    ARRAY_ID_FIELDS.each do |key|
      next unless fm.key?(key)

      value = fm[key]
      unless value.is_a?(Array)
        errors << "#{key} must be an array"
        next
      end

      value.each do |element|
        errors << "#{key} has invalid id: #{element.inspect}" unless valid_id?(element)
      end
    end

    { ok: missing.empty? && errors.empty?, missing: missing, errors: errors }
  end

  # Resolve an intent directory's primary md file and validate its frontmatter.
  # `plastic_home` is accepted for house-style parity (injectable) even though
  # validation reads the intent dir directly.
  def validate(intent_dir, plastic_home: File.join(Dir.home, ".plastic"))
    md_path = File.join(intent_dir, "#{File.basename(intent_dir)}.md")
    validate_frontmatter(parse_frontmatter(md_path))
  end
end
