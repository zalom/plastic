#!/usr/bin/env ruby
# encoding: UTF-8

# insights.rb - the blessed write path for an intent's `## Insights` section
# (intent 82). A sibling library to bridge.rb so the insight write path stays
# independent of the savepoint ledger (the spec forbids touching the ledger).
#
# Every entry leads with a fixed, machine-parseable prefix
# `{utc-iso8601} · {stage} · {author}` where the timestamp is `now.utc.iso8601`,
# the SAME convention `Bridge.append_savepoint_line` uses, so the store has one
# timestamp convention across both ledgers. Entries are append-only, newest at
# the BOTTOM (the [[34]] ordering law): the per-entry prefix is not prepending
# the entry, and existing entries are never reordered.

require "time"
require_relative "bridge"

module Insights
  HEADING = "## Insights"
  # The middle dot (U+00B7) with a single space on each side separates the
  # timestamp, stage, and author fields.
  SEPARATOR = " · "
  # A well-formed prefix: UTC ISO8601 timestamp to the second with a trailing
  # `Z`, then a non-empty stage, then a non-empty author, each ` · `-separated.
  PREFIX_RE = /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z · [^·]+ · [^·]+/.freeze

  # Append one insight entry at the BOTTOM of the `## Insights` section of the
  # intent file, creating the section (or the file) if absent. `now:` is the DI
  # seam: defaults to Time.now, tests inject Time.utc(...). Raises ArgumentError
  # if the assembled prefix is not well-formed (guard on write).
  def self.append_insight(intent_dir, text, stage:, author:, now: Time.now)
    prefix = "#{now.utc.iso8601}#{SEPARATOR}#{stage}#{SEPARATOR}#{author}"
    unless valid_insight_prefix?(prefix)
      raise ArgumentError, "malformed insight prefix: #{prefix.inspect}"
    end

    entry = "#{prefix} — #{text}"
    path = Bridge.intent_file(intent_dir)
    File.write(path, with_entry(File.exist?(path) ? File.read(path) : "", entry))
    entry
  end

  # Pure validator: true when `line` begins with a well-formed prefix. No IO,
  # no clock. Rejects a date-only prefix, a missing separator, a missing `Z`,
  # and sub-second precision.
  def self.valid_insight_prefix?(line)
    line.is_a?(String) && line.match?(PREFIX_RE)
  end

  # Insert `entry` at the bottom of the `## Insights` section of `content`,
  # preserving every existing line and their order. Pure string transform.
  def self.with_entry(content, entry)
    lines = content.empty? ? [] : content.split("\n", -1)
    heading_idx = lines.index { |l| l.strip == HEADING }
    return append_new_section(lines, entry) if heading_idx.nil?

    insert_at = section_end(lines, heading_idx)
    lines.insert(insert_at, entry)
    lines.join("\n")
  end

  # The insertion index for a new entry: just after the last non-empty content
  # line that belongs to the `## Insights` section (before the next `## `
  # heading or EOF).
  def self.section_end(lines, heading_idx)
    last_content = heading_idx
    idx = heading_idx + 1
    while idx < lines.length
      break if lines[idx].start_with?("## ")

      last_content = idx unless lines[idx].strip.empty?
      idx += 1
    end
    last_content + 1
  end

  # Append a fresh `## Insights` section (blank line, heading, entry) to the end
  # of the existing content.
  def self.append_new_section(lines, entry)
    body = lines.join("\n")
    body = body.sub(/\n+\z/, "") unless body.empty?
    pieces = body.empty? ? [] : [body, ""]
    pieces << HEADING << entry
    "#{pieces.join("\n")}\n"
  end
end
