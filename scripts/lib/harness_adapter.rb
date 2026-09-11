# encoding: UTF-8
# frozen_string_literal: true

# HarnessAdapter (intent 340b, G7c, n1): the one module in Plastic that knows
# a harness by name. It resolves the current key from config `agent.type`,
# renders a dispatch plan into that harness's instructions, and answers what
# the ledger should record. `runner step` calls it; nothing else in the
# runner does (spec D1).
#
# Pure: every input is an argument, nothing here reads ENV or a real
# config.yml itself - the caller (scripts/runner) owns loading real config,
# this module only resolves values out of what it is handed, the same
# discipline RunnerPolicy already holds for model resolution.
module HarnessAdapter
  module_function

  # The only two harnesses this module knows (spec D2). An unknown key -
  # config-authored or from `--harness` - always falls back to this rather
  # than to no adapter at all (matrix row 1.3): a plan with no rendering
  # under it is worse than a plan rendered for the wrong harness, because the
  # first is silent.
  DEFAULT_KEY = "claude-code"
  KNOWN_KEYS = %w[claude-code codex].freeze

  # kind -> the Claude Code agent type dispatched for it (spec Approach).
  # Verify and research carry no `Bash` in their own frontmatter (n2); this
  # table only names WHICH agent a kind maps to. An unknown kind gets
  # `work`'s row, the widest of the three, never no agent type at all
  # (matrix row 1.10), mirroring RunnerPolicy's own kind-table fallback.
  AGENT_TYPE_BY_KIND = {
    "work" => "plastic-node-work",
    "verify" => "plastic-node-verify",
    "research" => "plastic-node-research",
  }.freeze

  def agent_type_for_kind(kind)
    AGENT_TYPE_BY_KIND.fetch(kind.to_s, AGENT_TYPE_BY_KIND["work"])
  end

  # resolve_key(config:, override:) -> the harness key for one call (matrix
  # rows 1.1-1.3, 1.18). `override` (the CLI's `--harness KEY`, spec D2) wins
  # over `config`'s own `agent.type` for that one call; either source is
  # squashed (whitespace collapsed, matrix row 1.18) before it is even
  # compared, so a config-authored value carrying a tab or a newline can
  # never reach `NodeLedger` unsquashed and raise `ArgumentError` mid-dispatch,
  # after the packet is already built. A value that still is not one of
  # KNOWN_KEYS after squashing falls back to DEFAULT_KEY with a warning
  # (never to no adapter), so this method's return is always one of the two
  # known, clean strings - safe to hand straight to a ledger field.
  def resolve_key(config: {}, override: nil)
    raw = blank?(override) ? agent_type_from_config(config) : override.to_s
    squashed = squash(raw)
    return squashed if KNOWN_KEYS.include?(squashed)

    warn "harness_adapter: unknown harness #{raw.inspect}, falling back to #{DEFAULT_KEY.inspect}"
    DEFAULT_KEY
  end

  def agent_type_from_config(config)
    return DEFAULT_KEY unless config.is_a?(Hash)

    value = config.dig("agent", "type")
    value = config.dig(:agent, :type) if blank?(value)
    blank?(value) ? DEFAULT_KEY : value.to_s
  end
  private_class_method :agent_type_from_config

  def squash(text)
    text.to_s.strip.gsub(/\s+/, " ")
  end
  private_class_method :squash

  def blank?(value)
    value.nil? || value.to_s.strip.empty?
  end
  private_class_method :blank?

  # render(dispatched, harness:, return_contract:) -> the rendered
  # instruction block for `harness` (a String), or nil for an empty dispatch
  # list (matrix row 1.14: a step that dispatched nothing prints no
  # instruction block for a session to act on). `dispatched` is the runner's
  # own plan entries (RunnerDispatch's `:dispatched` shape): [{node:, kind:,
  # role:, model:, worktree:, packet:}, ...]. The model and the packet path
  # ride straight from each entry - never a fresh lookup (matrix row 1.11)
  # and never a summary (matrix row 1.12) - and `return_contract` (the exact
  # text RunnerDispatch::RETURN_CONTRACT already carries in the YAML plan)
  # renders exactly once, above every node, never per node (matrix row 1.13).
  def render(dispatched, return_contract:, harness: DEFAULT_KEY)
    entries = Array(dispatched)
    return nil if entries.empty?

    key = KNOWN_KEYS.include?(harness.to_s) ? harness.to_s : DEFAULT_KEY
    key == "codex" ? render_codex(entries, return_contract) : render_claude_code(entries, return_contract)
  end

  # The Claude Code rendering (spec Approach): per dispatched node, the agent
  # type from the kind, the model the plan already resolved, and the packet
  # path as the whole prompt.
  def render_claude_code(entries, return_contract)
    blocks = entries.map do |d|
      "Dispatch #{agent_type_for_kind(d[:kind])} for #{d[:node]} (model: #{d[:model]}):\n  prompt: #{d[:packet]}"
    end
    "#{return_contract.to_s.strip}\n\n#{blocks.join("\n\n")}\n"
  end
  private_class_method :render_claude_code

  # The Codex rendering: a Codex node runs end to end through `scripts/
  # node-run` (n6), which reads the ledger's own `running` line directly and
  # never through this printed block - so this names, per node, the same
  # facts the block gives Claude Code (kind, model, packet path) framed as
  # `node-run` calls, proving the seam renders SOMETHING for the second
  # harness rather than nothing (matrix row 1.27), without inventing detail
  # that belongs to n6's own adapter.
  def render_codex(entries, return_contract)
    blocks = entries.map do |d|
      "node-run #{d[:node]} (#{d[:kind]}, model: #{d[:model]}):\n  packet: #{d[:packet]}"
    end
    "#{return_contract.to_s.strip}\n\n#{blocks.join("\n\n")}\n"
  end
  private_class_method :render_codex
end
