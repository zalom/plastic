# encoding: UTF-8
# frozen_string_literal: true

require_relative "qmd_sync"
require_relative "power_tools"

# QmdHook - decision logic for the power-tools UserPromptSubmit hook (intents 66,
# 66b). Pure and dependency-injected: returns the additionalContext string to
# emit, or nil to emit nothing. The executable hook wires real deps and prints;
# this is unit-tested with a fake runner/detector (no real qmd, no network).
#
# When qmd is present it still injects scored qmd hits (intent 66), then appends
# the PowerTools mandate (a recommendation per present tool: qmd for finding
# intents, Enola-first for code navigation, falling back to Serena; intent 187
# added the enola_detector alongside the pre-existing serena_detector).
module QmdHook
  module_function

  MIN_PROMPT_LENGTH = 10

  def run(prompt:, cwd:, plastic_home:, runner: QmdSync.default_runner,
          detector: QmdSync.method(:detect), limit: 3, min_score: 0.5,
          serena_detector: nil, enola_detector: nil)
    serena_detector ||= -> { PowerTools.serena?(cwd: cwd) }
    enola_detector ||= -> { PowerTools.enola?(cwd: cwd) }
    qmd_present = !!detector.call
    serena_present = !!serena_detector.call
    enola_present = !!enola_detector.call
    return nil unless qmd_present || serena_present || enola_present

    p = prompt.to_s.strip
    # The hit SEARCH is the only expensive step and the only one gated by prompt
    # triviality: skip it for short or bare-"continue" prompts (and when qmd is
    # absent). The mandate itself is always-on for whichever tools are present.
    search_ok = qmd_present && p.length >= MIN_PROMPT_LENGTH && p.downcase != "continue"

    parts = []
    if search_ok
      collections = QmdSync.collections_for_cwd(cwd, plastic_home: plastic_home)
      hits = QmdSync.search(p, collections: collections, limit: limit,
                            min_score: min_score, runner: runner, detector: detector)
      if hits.any?
        parts << "Related / prior Plastic intents (qmd BM25, includes completed) - " \
                 "check before treating this as new work:"
        hits.each do |h|
          loc = h[:file].to_s.sub(%r{\Aqmd://}, "")
          pct = (h[:score] * 100).round
          parts << "- [#{pct}%] #{loc} - #{h[:title]}"
        end
        parts << ""
      end
    end

    mandate = PowerTools.mandate(cwd: cwd, qmd_detector: -> { qmd_present },
                                 serena_detector: -> { serena_present },
                                 enola_detector: -> { enola_present })
    parts << mandate if mandate
    return nil if parts.empty?
    parts.join("\n")
  end
end
