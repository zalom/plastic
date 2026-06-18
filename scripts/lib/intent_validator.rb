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

  # Sanctioned top-level intent sections, in order (intent 60b). The only
  # sanctioned `###` subsection is `### Decisions`, which is OPTIONAL (added after
  # brainstorming) and therefore never flagged as missing. This is the single
  # definition shared by the create gate, the validate-intent CLI, and doctor.
  SANCTIONED_SECTIONS = ["## Intent", "## Context", "## Outcome", "## Insights", "## Links"].freeze

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

    parse_frontmatter_text(File.read(path))
  rescue StandardError
    nil
  end

  # PURE: parse YAML frontmatter from a content STRING (no file IO). Returns the
  # parsed Hash, {} for an empty block, or nil when there is no parseable block.
  def parse_frontmatter_text(content)
    return nil unless content.is_a?(String) && content.start_with?("---")

    parts = content.split("---", 3)
    return nil if parts.length < 3

    YAML.safe_load(parts[1], permitted_classes: [Date, Time]) || {}
  rescue StandardError
    nil
  end

  # PURE: strip the leading YAML frontmatter block from a content STRING,
  # returning the body text (everything after the closing `---`). When there is
  # no frontmatter block, the whole content is the body.
  def body_of(content)
    return "" unless content.is_a?(String)
    return content unless content.start_with?("---")

    parts = content.split("---", 3)
    parts.length < 3 ? content : parts[2]
  end

  # PURE: given the intent file body text, return sanctioned-section findings.
  # Flags any unknown top-level `## ` heading and any missing sanctioned section.
  # Ignores `### ` subsections entirely (Decisions is optional and lives under
  # Context). Returns { ok:, missing: [section names], unknown: [heading strings] }.
  def validate_sections(body)
    headings = body.to_s.lines.filter_map do |l|
      s = l.strip
      s if s.start_with?("## ") && !s.start_with?("### ")
    end
    present = headings & SANCTIONED_SECTIONS
    missing = SANCTIONED_SECTIONS - present
    unknown = headings - SANCTIONED_SECTIONS
    { ok: missing.empty? && unknown.empty?, missing: missing, unknown: unknown }
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

  # PURE: combine the frontmatter result with section-structure findings for a
  # content STRING. Returns the frontmatter result hash extended with
  # :section_missing, :section_unknown, and folded section errors; :ok is the AND
  # of frontmatter and sections. Lets the create gate validate proposed content
  # (no file on disk) with the same definition as the CLI and doctor.
  def validate_content(content)
    fm_result = validate_frontmatter(parse_frontmatter_text(content))
    sections = validate_sections(body_of(content))
    merge_sections(fm_result, sections)
  end

  # Fold section findings into a frontmatter result hash (shared by validate and
  # validate_content). Does not mutate the input.
  def merge_sections(fm_result, sections)
    errors = fm_result[:errors].dup
    sections[:unknown].each { |h| errors << "unknown section: #{h}" }
    sections[:missing].each { |s| errors << "missing required section: #{s}" }
    {
      ok: fm_result[:ok] && sections[:ok],
      missing: fm_result[:missing],
      errors: errors,
      section_missing: sections[:missing],
      section_unknown: sections[:unknown],
    }
  end

  # Resolve an intent directory's primary md file and validate its frontmatter
  # AND its sanctioned section structure. `plastic_home` is accepted for
  # house-style parity (injectable) even though validation reads the dir directly.
  def validate(intent_dir, plastic_home: File.join(Dir.home, ".plastic"))
    md_path = File.join(intent_dir, "#{File.basename(intent_dir)}.md")
    content = File.exist?(md_path) ? File.read(md_path) : nil
    validate_content(content)
  end
end
