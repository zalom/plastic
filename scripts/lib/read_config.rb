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

# Resolves one config key the project -> global -> built-in way, in process.
module ReadConfig
  # The caller-facing knobs for resolve: an explicit fallback value, which
  # project (if any) to check ahead of the global config, which harness to
  # read agent-model keys for, and which global home to read from.
  Options = Struct.new(:default, :project, :harness, :plastic_home)

  # The two already-loaded config hashes lookup checks, project then global.
  Sources = Struct.new(:project_config, :global_config)

  # What resolve_fallback needs once the direct lookup comes back empty.
  Fallback = Struct.new(:key, :canonical, :default)

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

  # Canonicalizes a --harness value and reads its agents.models/agents.efforts
  # entries, both the shipped default and whatever a loaded config overrides.
  module Harness
    # Raised when --harness names anything but claude or codex.
    class InvalidHarness < StandardError; end

    AGENT_KEY = /\Aagents\.(models|efforts)\.([^.]+)\z/

    def self.canonical(value)
      return unless value

      text = value.to_s
      return "claude" if %w[claude claude-code].include?(text)
      return "codex" if text == "codex"

      raise InvalidHarness, "--harness must be claude or codex"
    end

    def self.agent_value(config, key, harness)
      match = AGENT_KEY.match(key)
      return nil unless match

      section, agent = match.captures
      (section == "models") ? AgentModels.models_section(config, harness: harness)[agent] : AgentModels.efforts_section(config, harness)[agent]
    end

    def self.shipped_default(key, harness)
      match = AGENT_KEY.match(key)
      return nil unless match

      (match[1] == "models") ? AgentModels.shipped_model_for(match[2], harness: harness) : AgentModels::DEFAULT_EFFORT
    end
  end

  InvalidHarness = Harness::InvalidHarness

  def self.load_yaml(path)
    return {} unless File.exist?(path)
    YAML.safe_load_file(path) || {}
  rescue => error
    warn "Warning: failed to parse #{path}: #{error.message}"
    {}
  end

  def self.dig_key(hash, dotted_key)
    dotted_key.split(".").reduce(hash) do |value, segment|
      return nil unless value.is_a?(Hash) && value.key?(segment)

      value[segment]
    end
  end

  def self.format_value(value)
    case value
    when Hash, Array then JSON.generate(value)
    when String, Numeric, true, false then value.to_s
    else ""
    end
  end

  # Resolves a config value the same way the CLI does: project config, then
  # global config, then an explicit default, then the harness-aware shipped
  # default, then the built-in DEFAULTS. Returns the raw value (a string,
  # number, array, or hash), never the CLI's stringified form.
  def self.resolve(key, options = Options.new)
    canonical = Harness.canonical(options.harness)
    value = lookup(load_sources(options), key, canonical)

    resolve_fallback(value, Fallback.new(key: key, canonical: canonical, default: options.default))
  end

  def self.load_sources(options)
    plastic_home = options.plastic_home || ENV.fetch("PLASTIC_HOME", File.expand_path("~/.plastic"))
    project = options.project
    project_config = project ? load_yaml(File.join(project, ".plastic_store", "config.yml")) : {}
    Sources.new(project_config: project_config, global_config: load_yaml(File.join(plastic_home, "config.yml")))
  end

  # value is nil only when neither config set the key; a stored `false` (the
  # one non-string config value this module carries, runner.stop_hook)
  # reaches here as itself, never as a reason to keep looking.
  def self.resolve_fallback(value, fallback)
    return value unless NilClass === value

    default = fallback.default
    default || shipped_or_builtin_default(fallback)
  end

  def self.shipped_or_builtin_default(fallback)
    key, canonical = fallback.key, fallback.canonical
    shipped = canonical && Harness.shipped_default(key, canonical)
    shipped || dig_key(DEFAULTS, key)
  end

  def self.lookup(sources, key, canonical)
    project_config, global_config = sources.project_config, sources.global_config
    if canonical
      [Harness.agent_value(project_config, key, canonical), Harness.agent_value(global_config, key, canonical)].compact.first
    else
      [dig_key(project_config, key), dig_key(global_config, key)].compact.first
    end
  end
end
