# encoding: UTF-8
# frozen_string_literal: true

require_relative "qmd_sync"
require_relative "power_tools"

# QmdHook - decision logic for the power-tools UserPromptSubmit hook (intents 66,
# 66b, 187, 246). Pure and dependency-injected: returns the additionalContext
# string to emit, or nil to emit nothing. The executable hook wires real deps and
# prints; this is unit-tested with fake detectors (no real qmd, no network, no
# subprocess at all).
#
# It emits exactly one thing: the PowerTools mandate, one recommendation line per
# present tool (qmd for finding intents, Enola-first for code navigation, falling
# back to Serena; intent 187 added the enola_detector alongside the pre-existing
# serena_detector).
#
# Intent 246 removed the scored qmd hit injection this hook used to prepend.
# Intent 225 measured that injection at 0.24 intent-level recall@3 against a plain
# ripgrep control at 0.18, while agent-driven `qmd query` scored 0.71. The failure
# was recall, not latency, so caching and async were both rejected. QmdSync.search
# is untouched and still backs the `scripts/qmd-sync search` CLI verb. All three
# detectors are PATH and marker-file walks with no subprocess, which is why what is
# left costs about a tenth of a second.
module QmdHook
  module_function

  def run(cwd:, detector: QmdSync.method(:detect), serena_detector: nil,
          enola_detector: nil)
    serena_detector ||= -> { PowerTools.serena?(cwd: cwd) }
    enola_detector ||= -> { PowerTools.enola?(cwd: cwd) }
    qmd_present = !!detector.call
    serena_present = !!serena_detector.call
    enola_present = !!enola_detector.call
    return nil unless qmd_present || serena_present || enola_present

    PowerTools.mandate(cwd: cwd, qmd_detector: -> { qmd_present },
                       serena_detector: -> { serena_present },
                       enola_detector: -> { enola_present })
  end
end
