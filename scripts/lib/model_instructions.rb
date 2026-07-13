# frozen_string_literal: true

require "fileutils"

# Model-conditional instruction injection (intent 185). Pure logic, dependency
# injected: no real /tmp, no real config, no real plugin install touched here, so
# callers (hooks) stay hermetic under test. Every public entry point fails open:
# a raise anywhere becomes "no injection", never a blocked session.
module ModelInstructions
  MARKER_PREFIX = "plastic-model-instructions-"
  CACHE_PREFIX  = "plastic-model-"

  # Model family -> shipped instruction file under model_instructions/. This is
  # the whole extension surface for a new model family: one new entry here plus
  # one new shipped file, nothing else in the injection logic changes. Today's
  # only entry targets Opus 4.8 as the executor.
  MODEL_MAP = {
    /opus/i => "operating-manual.md"
  }.freeze

  POINTER_TEXT = <<~TEXT.freeze
    ## Advisor available
    This install ships plastic-advisor, a consultation agent for expensive
    reasoning (model per advisor.model, fable by default). Consult in natural
    prose with a self-contained brief: a TIER line (S: bounded decision, verdict
    + biggest risk; M: plan or plan-review with per-step checks + risk map; L:
    architecture and one-way doors, adds rival
    approaches and kill criteria), the goal and the decision it feeds, max 3
    questions, your own candidate answer to attack, evidence labeled
    verified/inferred/assumed, constraints, one-way doors. Where the harness supports
    per-call effort, raise it to xhigh for L consultations. Before your first
    consultation this session, read the shipped Advisor Protocol
    (model_instructions/advisor-protocol.md under the plugin root, or
    ~/.plastic/model_instructions on installs). Escalate a tier only when failure
    cost justifies it.
  TEXT

  module_function

  # The MODEL_MAP file for the given model string, or nil when no family matches.
  # Tolerant of nil / any object.
  def file_for(model)
    _pattern, file = MODEL_MAP.find { |pattern, _file| model.to_s =~ pattern }
    file
  end

  # config_reader is a zero-arg callable returning a raw config value (a boolean,
  # a string, or nil). Only an explicit false (boolean or the string "false")
  # disables; nil, missing, or a raising reader all count as enabled, the shared
  # fail-open semantics for both advisor.enabled and model_instructions.opus.
  def enabled?(config_reader)
    value = config_reader.call
    return true if value.nil?
    return false if value == false
    value.to_s.strip.downcase != "false"
  rescue StandardError
    true
  end

  # The shipped instruction text for `file`. Tries plugin_root/model_instructions
  # first (when plugin_root is non-empty and the file reads), then falls back to
  # fallback_dir (default ~/.plastic/model_instructions, where the installer
  # syncs both documents on every install and update). nil when neither
  # resolves, so a simulated manifest install with an empty CLAUDE_PLUGIN_ROOT
  # still finds the file through the fallback.
  def instruction_text(file, plugin_root, fallback_dir: File.expand_path("~/.plastic/model_instructions"))
    unless plugin_root.to_s.empty?
      begin
        return File.read(File.join(plugin_root.to_s, "model_instructions", file))
      rescue StandardError
        # fall through to fallback_dir
      end
    end
    File.read(File.join(fallback_dir.to_s, file))
  rescue StandardError
    nil
  end

  def pointer_text
    POINTER_TEXT
  end

  # Decide whether to inject, and if so, mark the session so the primary
  # (session-start) and fallback (UserPromptSubmit) paths never double-inject:
  # both call this with the same state_dir/session_id, so the marker file is
  # shared between them. Two independent config gates: model_instructions_reader
  # (model_instructions.opus) controls whether the instruction text injects at
  # all; advisor_reader (advisor.enabled) controls only whether the advisor
  # pointer paragraph is appended, so the instruction text can still land when
  # the advisor agent is not installed.
  def injection(model:, session_id:, plugin_root:, state_dir:, model_instructions_reader:, advisor_reader:,
                fallback_dir: File.expand_path("~/.plastic/model_instructions"))
    file = file_for(model)
    return nil unless file
    return nil unless enabled?(model_instructions_reader)

    marker = File.join(state_dir.to_s, "#{MARKER_PREFIX}#{session_id}")
    return nil if File.exist?(marker)

    text = instruction_text(file, plugin_root, fallback_dir: fallback_dir)
    return nil unless text

    FileUtils.mkdir_p(state_dir.to_s)
    File.write(marker, "")

    enabled?(advisor_reader) ? "#{text}\n\n#{pointer_text}" : text
  rescue StandardError
    nil
  end
end
