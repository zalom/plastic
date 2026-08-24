# encoding: UTF-8
# frozen_string_literal: true

require_relative "rule_catalog"

# DoctorExclusions - resolves, reads, and parses one store's per-store `doctor-exclusions`
# table (intent 274): the record of knowingly-exempt (intent_id, rule) pairs that lets doctor
# skip a finding it can never legitimately repair (219 D6 forbids inventing a disposition for
# an unrepairable gap).
#
# Location (spec D6): sibling to that store's INDEX.md, resolved via `path_for` from the same
# `store[:index]` Doctor#done_signal_stores already yields - zero new store-discovery logic.
# Deliberately no `.md` extension: this is a config table, not a markdown document indexed by
# QMD or walked by lifecycle machinery.
#
# Format (spec D6), `/etc/hosts`-shaped: `rule_name id id id`, one rule per line. Blank lines
# and `#`-comment lines are ignored. Duplicate rule lines union their ids.
#
# Error contract (spec D5): fail open, loud in doctor. A missing file is the normal case -
# zero exclusions, zero errors, identical to before this file existed. A malformed line never
# excludes anything (fail milder than the bug: a typo must not silently suppress a real
# regression) and contributes one error string naming its 1-based line number. An unreadable
# file contributes one error and zero exclusions. This module NEVER raises.
module DoctorExclusions
  module_function

  FILENAME = "doctor-exclusions"

  # Same shape test/packaging_no_store_ids_test.rb already defines for a real Folgezettel id:
  # digit-leading, then any mix of letters and digits.
  FOLGEZETTEL_ID = /\A\d+[a-zA-Z0-9]*\z/

  def path_for(index_path)
    File.join(File.dirname(index_path), FILENAME)
  end

  # PURE. { rules: { rule_name => [ids] }, errors: [String] }. A line producing any error
  # contributes nothing to rules; duplicate rule lines union their ids without an error.
  def parse(text)
    rules = {}
    errors = []

    text.to_s.each_line.with_index(1) do |raw_line, n|
      line = raw_line.strip
      next if line.empty? || line.start_with?("#")

      tokens = line.split
      rule = tokens.shift
      line_errors = []

      line_errors << "line #{n}: rule \"#{rule}\" lists no intent ids" if tokens.empty?
      unless RuleCatalog.excludable_check?(rule)
        line_errors << "line #{n}: unknown or non-excludable rule \"#{rule}\""
      end
      tokens.each do |tok|
        line_errors << "line #{n}: \"#{tok}\" is not a Folgezettel intent id" unless tok =~ FOLGEZETTEL_ID
      end

      if line_errors.empty?
        (rules[rule] ||= []).concat(tokens)
        rules[rule].uniq!
      else
        errors.concat(line_errors)
      end
    end

    { rules: rules, errors: errors }
  end

  # IO. `parse`'s shape plus `path:`. Never raises: a missing file is the normal case (zero
  # exclusions, zero errors); an unreadable file (permission, is-a-directory, any
  # SystemCallError) yields one error and zero exclusions.
  def load(index_path)
    path = path_for(index_path)
    return { rules: {}, errors: [], path: path } unless File.exist?(path)

    parse(File.read(path)).merge(path: path)
  rescue SystemCallError => e
    { rules: {}, errors: ["#{path}: unreadable (#{e.message})"], path: path }
  end

  # Rule names excluding `intent_id` in an already-`load`ed result. [] when none.
  def rules_for(loaded, intent_id)
    loaded[:rules].select { |_rule, ids| ids.include?(intent_id) }.keys
  end
end
