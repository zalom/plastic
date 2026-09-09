# encoding: UTF-8
# frozen_string_literal: true

require "json"
require "time"

# ScreenCensus (intent 331a, T3) - the hermetic port of resources/probes/
# census.rb. The probe scanned Dir["~/.claude/projects/*/*.jsonl"], the
# owner's real transcripts; that is neither hermetic nor reproducible in the
# suite. `count` takes an explicit file list instead, so a test can point it
# at a checked-in fixture transcript.
module ScreenCensus
  OPEN = /\A\s*(## [▶✔]|▶ In delivery|✔ \S)/
  ANY  = /(^|\n)\s*(## [▶✔]|▶ In delivery|✔ \d)/

  module_function

  # Returns { "YYYY-MM-DD" => { "total" => n, "opens_reply" => n,
  # "prose_first" => n, "fenced" => n } } for every assistant text reply, in
  # any of `files`, that carries a screen anywhere in its text.
  def count(files)
    rows = Hash.new { |h, k| h[k] = Hash.new(0) }
    files.each do |f|
      File.foreach(f) do |line|
        j = begin
          JSON.parse(line)
        rescue JSON::ParserError
          next
        end
        next unless j["type"] == "assistant"

        content = j.dig("message", "content")
        next unless content.is_a?(Array)

        texts = content.select { |c| c["kind"] == "text" || c["type"] == "text" }.map { |c| c["text"].to_s }
        next if texts.empty?

        full = texts.join
        next unless full =~ ANY

        day = begin
          Time.parse(j["timestamp"]).strftime("%Y-%m-%d")
        rescue StandardError, TypeError
          "unknown"
        end
        kind = if texts.first =~ OPEN then "opens_reply"
               elsif full =~ /```[^\n]*\n\s*(## [▶✔]|▶ In delivery|✔ )/ then "fenced"
               else "prose_first" end
        rows[day][kind] += 1
        rows[day]["total"] += 1
      end
    end
    rows
  end
end
