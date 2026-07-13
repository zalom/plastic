# frozen_string_literal: true

require "fileutils"

# Model-conditional Opus manual injection (intent 185). Pure logic, dependency
# injected: no real /tmp, no real config, no real plugin install touched here, so
# callers (hooks) stay hermetic under test. Every public entry point fails open:
# a raise anywhere becomes "no injection", never a blocked session.
module OpusManual
  MARKER_PREFIX = "plastic-opus-manual-"
  CACHE_PREFIX  = "plastic-model-"

  POINTER_TEXT = <<~TEXT.freeze
    ## Fable advisor available
    This install ships consultation agents you can dispatch for expensive reasoning:
    fable-advisor-s (effort low: one bounded decision, verdict + biggest risk),
    fable-advisor-m (effort medium: plan or plan-review, decision + stepped plan + risk
    map), fable-advisor-l (effort xhigh: architecture, one-way doors, deadlocks; adds
    kill criteria). Consult in natural prose with a self-contained brief: goal and the
    decision it feeds, max 3 questions, your own candidate answer to attack, evidence
    labeled verified/inferred/assumed, constraints, one-way doors. Before your first
    consultation this session, read manuals/advisor-protocol.md under the Plastic
    plugin root. Escalate a tier only when failure cost justifies it.
  TEXT

  module_function

  # True when the given model string names Opus. Tolerant of nil / any object.
  def opus?(model)
    !!(model.to_s =~ /opus/i)
  end

  # config_reader is a zero-arg callable returning the raw context.opus_manual
  # config value (a boolean, a string, or nil). Only an explicit false (boolean
  # or the string "false") disables; nil, missing, or a raising reader all count
  # as enabled, matching the fail-open default of intent 185.
  def enabled?(config_reader)
    value = config_reader.call
    return true if value.nil?
    return false if value == false
    value.to_s.strip.downcase != "false"
  rescue StandardError
    true
  end

  # The shipped manual text, or nil if plugin_root is unset or the file is
  # missing/unreadable.
  def manual_text(plugin_root)
    return nil if plugin_root.to_s.empty?
    File.read(File.join(plugin_root.to_s, "manuals", "operating-manual.md"))
  rescue StandardError
    nil
  end

  def pointer_text
    POINTER_TEXT
  end

  # Decide whether to inject, and if so, mark the session so the primary
  # (session-start) and fallback (UserPromptSubmit) paths never double-inject:
  # both call this with the same state_dir/session_id, so the marker file is
  # shared between them.
  def injection(model:, session_id:, plugin_root:, state_dir:, config_reader:)
    return nil unless opus?(model)
    return nil unless enabled?(config_reader)

    marker = File.join(state_dir.to_s, "#{MARKER_PREFIX}#{session_id}")
    return nil if File.exist?(marker)

    text = manual_text(plugin_root)
    return nil unless text

    FileUtils.mkdir_p(state_dir.to_s)
    File.write(marker, "")

    "#{text}\n\n#{pointer_text}"
  rescue StandardError
    nil
  end
end
