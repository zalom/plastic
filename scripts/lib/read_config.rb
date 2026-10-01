# encoding: UTF-8
# frozen_string_literal: true

# Core half of read-config (intent 397): the project -> global -> built-in
# defaults resolution, extracted so a caller already running in the same
# Ruby process (the SessionStart hook, among others) can read a config value
# in-process instead of paying a subprocess spawn for every lookup.
# scripts/read-config requires this file and stays the CLI entry: argument
# parsing, --migrate, and stdout formatting remain there.

require "yaml"
require "json"
require_relative "agent_models"

module ReadConfig
  DEFAULTS = {
    "version" => 3,
    "stale_threshold_days" => 3,
    # Absolute token counts for a 1M window, 15 and 25 percent (intent 355, n5, D7).
    "context_offer_tokens" => 150_000,
    "context_insist_tokens" => 250_000,
    "execution_mode" => "subagent-driven",
    "hash_length" => 6,
    "hash_algorithm" => "sha256-base36",
    "max_slug_words" => 5,
    "project_roots" => ["~/.plastic/projects"],
    "deprecations_dismissed" => [],
    "config_asks_dismissed" => [],
    "agent" => {
      "type" => "claude-code",
      "parallel_mode" => "linear"
    },
    "agents" => {
      "models" => AgentModels::TIER_DEFAULTS
    },
    "architect" => {
      "style" => nil
    },
    # Intent 340b (G7c, n4, D9): the Stop hook's runtime arm. Off until the
    # owner's C32 ruling; read-config emits it as the string "false", which
    # StopGate parses as a boolean itself rather than trusting.
    "runner" => {
      "stop_hook" => false
    }
  }.freeze

  class InvalidHarness < StandardError; end

  def self.load_yaml(path)
    return {} unless File.exist?(path)
    YAML.safe_load_file(path) || {}
  rescue => e
    warn "Warning: failed to parse #{path}: #{e.message}"
    {}
  end

  def self.dig_key(hash, dotted_key)
    keys = dotted_key.split(".")
    value = hash
    keys.each do |k|
      return nil unless value.is_a?(Hash) && value.key?(k)
      value = value[k]
    end
    value
  end

  def self.format_value(value)
    case value
    when Hash, Array
      JSON.generate(value)
    when nil
      ""
    else
      value.to_s
    end
  end

  def self.canonical_harness(value)
    return nil if value.nil?
    return "claude" if %w[claude claude-code].include?(value.to_s)
    return "codex" if value.to_s == "codex"

    raise InvalidHarness, "--harness must be claude or codex"
  end

  def self.harness_agent_value(config, key, harness)
    match = key.match(/\Aagents\.(models|efforts)\.([^.]+)\z/)
    return nil unless match

    section, agent = match.captures
    if section == "models"
      AgentModels.models_section(config, harness: harness)[agent]
    else
      AgentModels.efforts_section(config, harness)[agent]
    end
  end

  def self.harness_shipped_default(key, harness)
    match = key.match(/\Aagents\.(models|efforts)\.([^.]+)\z/)
    return nil unless match

    (match[1] == "models") ? AgentModels.shipped_model_for(match[2], harness: harness) : AgentModels::DEFAULT_EFFORT
  end

  # Resolves a config value the same way the CLI does: project config, then
  # global config, then an explicit default, then the harness-aware shipped
  # default, then the built-in DEFAULTS. Returns the raw value (a string,
  # number, array, or hash), never the CLI's stringified form.
  def self.resolve(key, default: nil, project: nil, harness: nil,
    plastic_home: ENV.fetch("PLASTIC_HOME", File.expand_path("~/.plastic")))
    global_config = load_yaml(File.join(plastic_home, "config.yml"))
    project_config = project ? load_yaml(File.join(project, ".plastic_store", "config.yml")) : {}
    canonical = canonical_harness(harness)

    value = lookup(project_config, global_config, key, canonical)
    value = default if value.nil? && default
    value = harness_shipped_default(key, canonical) if value.nil? && canonical
    value.nil? ? dig_key(DEFAULTS, key) : value
  end

  def self.lookup(project_config, global_config, key, canonical)
    if canonical
      value = harness_agent_value(project_config, key, canonical)
      value.nil? ? harness_agent_value(global_config, key, canonical) : value
    else
      value = dig_key(project_config, key)
      value.nil? ? dig_key(global_config, key) : value
    end
  end
end
