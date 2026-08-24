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
#
# The file is also the input to a drift check (intent 280): `dead_rows` below reports rows that
# suppress nothing this run, so a governance record that only ever grows does not silently decay
# into an unreviewable list.
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
  #
  # `scrub` (never raises) before any regex/String op: a hand-edited file can carry a byte
  # sequence invalid in its declared encoding (e.g. a stray Latin-1 byte in a comment), and
  # String#strip/split/=~ all raise Encoding::CompatibilityError on that input. Scrubbing
  # replaces the invalid byte with U+FFFD and keeps this module's never-raises contract (D5)
  # true for every input, not just well-formed UTF-8.
  def parse(text)
    rules = {}
    errors = []

    text.to_s.scrub.each_line.with_index(1) do |raw_line, n|
      line = raw_line.strip
      next if line.empty? || line.start_with?("#")

      line = line.sub(/(?:\A|\s)#.*\z/, "").rstrip
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

  # PURE (intent 280, hardened by post-review fixes). Dead rows: registered (rule, id) pairs that
  # suppressed nothing this run.
  #
  # `consumed` is { rule_name => [intent_id] }, built by the CALLER from findings that actually
  # fired during its own directory walk. `known_ids` is every intent id with a REAL DIRECTORY in
  # the store - resolved by the caller against the store's own directory listing, never against
  # which ids a particular walk happened to visit (review fix: an id can have a real directory on
  # disk without being listed in INDEX.md at all, a de-indexed "ghost"; deriving known_ids from
  # walk membership alone misclassified that ghost as :no_intent - deleted - even though its
  # directory plainly still exists). `evaluated_ids` (defaults to `known_ids` when omitted) is the
  # narrower set of ids this run's walk actually judged one way or the other. An id with a real
  # directory that was never evaluated this run (on disk, but absent from INDEX so the walk never
  # visited it) carries no evidence either way and is left out of the result entirely - never
  # called dead, never called live. None of `loaded`, `consumed`, `known_ids`, or `evaluated_ids`
  # is derived from the exclusion file itself: this function is handed all of them and has no way
  # to reach the file, which is what keeps it from becoming the intent 200 self-diff (a check that
  # only ever proves the file agrees with itself - see 208).
  #
  # Only rules present as a KEY in `consumed` are considered at all: a rule this run's walk never
  # tracked consumption for (e.g. a newly-excludable check no caller has been updated to evaluate
  # yet) is "not evaluated" for the whole rule, and none of its rows are ever reported dead -
  # reporting them would assume evidence the caller never actually gathered.
  #
  # Genuinely pure and non-raising: reads with `fetch`/`Array()` throughout, never indexes a
  # default-proc Hash with `[]` (doing so would silently ADD that key to the CALLER's own hash as
  # a side effect - not pure), and tolerates a nil/empty/malformed `loaded`, a nil `consumed`, and
  # nil `known_ids`/`evaluated_ids`.
  #
  # Returns [{ rule:, id:, reason: }], reason being :no_finding (a real directory, evaluated this
  # run, but the rule fired nothing to suppress) or :no_intent (no real directory at all - a typo,
  # or the intent was deleted). Order is stable: rule name, then id.
  def dead_rows(loaded, consumed: {}, known_ids: [], evaluated_ids: nil)
    rules = (loaded || {})[:rules] || {}
    consumed = consumed || {}
    known = Array(known_ids)
    evaluated = evaluated_ids.nil? ? known : Array(evaluated_ids)

    rules.keys.sort.select { |rule| consumed.key?(rule) }.flat_map do |rule|
      live = Array(consumed.fetch(rule, []))
      dead_ids = (Array(rules[rule]) - live).sort

      dead_ids.each_with_object([]) do |id, acc|
        is_known = known.include?(id)
        next if is_known && !evaluated.include?(id) # on disk, never evaluated - no evidence

        acc << { rule: rule, id: id, reason: is_known ? :no_finding : :no_intent }
      end
    end
  end
end
