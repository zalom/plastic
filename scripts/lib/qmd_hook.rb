# encoding: UTF-8
# frozen_string_literal: true

require_relative "qmd_sync"

# QmdHook — decision logic for the qmd-first UserPromptSubmit hook (intent 66).
# Pure and dependency-injected: returns the additionalContext string to emit, or
# nil to emit nothing. The executable hook wires real deps and prints; this is
# unit-tested with a fake runner/detector (no real qmd, no network).
module QmdHook
  module_function

  MIN_PROMPT_LENGTH = 10
  REMINDER = "qmd is available: query it (`qmd search` / `qmd query` over the " \
             "`plastic-*` collections) before grep/Read when gathering intent " \
             "context (sources/chain) or checking whether this work already " \
             "exists as an intent."

  def run(prompt:, cwd:, plastic_home:, runner: QmdSync.default_runner,
          detector: QmdSync.method(:detect), limit: 3, min_score: 0.5)
    return nil unless detector.call
    p = prompt.to_s.strip
    return nil if p.length < MIN_PROMPT_LENGTH
    return nil if p.downcase == "continue"

    collections = QmdSync.collections_for_cwd(cwd, plastic_home: plastic_home)
    hits = QmdSync.search(p, collections: collections, limit: limit,
                          min_score: min_score, runner: runner, detector: detector)

    parts = []
    if hits.any?
      parts << "Related / prior Plastic intents (qmd BM25, includes completed) — " \
               "check before treating this as new work:"
      hits.each do |h|
        loc = h[:file].to_s.sub(%r{\Aqmd://}, "")
        pct = (h[:score] * 100).round
        parts << "- [#{pct}%] #{loc} — #{h[:title]}"
      end
      parts << ""
    end
    parts << REMINDER
    parts.join("\n")
  end
end
