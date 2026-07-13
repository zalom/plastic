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
    This install ships plastic-fable-advisor, a consultation agent for expensive
    reasoning (model fable). Consult in natural prose with a self-contained brief:
    a TIER line (S: bounded decision, verdict + biggest risk; M: plan or plan-review
    with per-step checks + risk map; L: architecture and one-way doors, adds rival
    approaches and kill criteria), the goal and the decision it feeds, max 3
    questions, your own candidate answer to attack, evidence labeled
    verified/inferred/assumed, constraints, one-way doors. Where the harness supports
    per-call effort, raise it to xhigh for L consultations. Before your first
    consultation this session, read the shipped Advisor Protocol
    (manuals/advisor-protocol.md under the plugin root, or ~/.plastic/manuals on
    installs). Escalate a tier only when failure cost justifies it.
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

  # The shipped manual text. Tries plugin_root/manuals first (when plugin_root is
  # non-empty and the file reads), then falls back to fallback_dir (default
  # ~/.plastic/manuals, where the installer syncs both manuals on every install
  # and update). nil when neither resolves, so a simulated manifest install with
  # an empty CLAUDE_PLUGIN_ROOT still finds the manual through the fallback.
  def manual_text(plugin_root, fallback_dir: File.expand_path("~/.plastic/manuals"))
    unless plugin_root.to_s.empty?
      begin
        return File.read(File.join(plugin_root.to_s, "manuals", "operating-manual.md"))
      rescue StandardError
        # fall through to fallback_dir
      end
    end
    File.read(File.join(fallback_dir.to_s, "operating-manual.md"))
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
  def injection(model:, session_id:, plugin_root:, state_dir:, config_reader:,
                fallback_dir: File.expand_path("~/.plastic/manuals"))
    return nil unless opus?(model)
    return nil unless enabled?(config_reader)

    marker = File.join(state_dir.to_s, "#{MARKER_PREFIX}#{session_id}")
    return nil if File.exist?(marker)

    text = manual_text(plugin_root, fallback_dir: fallback_dir)
    return nil unless text

    FileUtils.mkdir_p(state_dir.to_s)
    File.write(marker, "")

    "#{text}\n\n#{pointer_text}"
  rescue StandardError
    nil
  end
end
