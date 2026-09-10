# encoding: UTF-8
# frozen_string_literal: true

require "yaml"

# NodeReturn (intent 340, G7, n4): the closed schema an executor's return must
# satisfy before RunnerAbsorb ever writes a ledger line from it. #parse reads
# one YAML document and returns a Result struct (ok: true, every field
# populated) or a named failure (ok: false, errors: [...]) - never raises
# across its own boundary, and never trusts anything the caller has not
# already scrubbed to valid UTF-8 (it scrubs again itself, defense in depth).
#
# The key set is closed (ALLOWED_KEYS): an unknown key is a refusal, not a
# silently dropped field, so the contract between an executor and the runner
# cannot erode without the next return going red. The status vocabulary is
# closed too (STATUSES), and each status carries its own required field
# (REQUIRED_FIELDS) - `done` needs `commit`, `needs_decision` needs
# `question`, `failed_verification` and `blocked` need `reason`.
#
# `proposed_nodes` and `proposed_edges` entries are pinned sub-schemas, not
# left to whatever an executor happens to emit: a node entry carries `kind`,
# `title` and `needs`, with optional `files` and `budget`; an edge entry
# carries `from` and `to`. A malformed entry anywhere in either list refuses
# the whole return, the same as any other schema violation.
#
# `findings` is coerced to an array of plain strings and capped, both in
# count (MAX_FINDINGS) and per-entry length (MAX_FINDING_LENGTH), so a
# nested structure or a runaway array can never reach the Insight line
# RunnerAbsorb builds from it.
module NodeReturn
  module_function

  STATUSES = %w[done failed_verification needs_decision blocked].freeze

  ALLOWED_KEYS = %w[
    node status commit summary findings proposed_nodes proposed_edges question reason
  ].freeze

  REQUIRED_FIELDS = {
    "done" => %w[commit],
    "needs_decision" => %w[question],
    "failed_verification" => %w[reason],
    "blocked" => %w[reason],
  }.freeze

  PROPOSED_NODE_REQUIRED = %w[kind title needs].freeze
  PROPOSED_EDGE_REQUIRED = %w[from to].freeze

  MAX_FINDINGS = 20
  MAX_FINDING_LENGTH = 500

  Result = Struct.new(
    :ok, :node, :status, :commit, :summary, :findings, :proposed_nodes, :proposed_edges,
    :question, :reason, :errors,
    keyword_init: true
  )

  # parse(text) -> a Result. `text` is scrubbed to valid UTF-8 before it ever
  # reaches the YAML parser (row 4.12), and loaded with aliases disabled and
  # no permitted classes (row 4.11: an alias or anchor bomb is refused, not
  # expanded). Every failure path returns a Result with ok: false and a
  # human-readable errors: list; nothing here ever raises out to the caller.
  def parse(text)
    scrubbed = text.to_s.dup.force_encoding("UTF-8").scrub
    loaded = safe_load(scrubbed)
    return failure([loaded[:error]]) unless loaded[:ok]

    doc = loaded[:value]
    return failure(["return must be a YAML mapping, got #{doc.class}"]) unless doc.is_a?(Hash)

    doc = stringify_keys(doc)
    unknown = doc.keys - ALLOWED_KEYS
    return failure(["unknown key(s): #{unknown.join(', ')}"]) if unknown.any?

    return failure(["missing node id (node:)"]) unless present?(doc["node"])

    status = doc["status"].to_s
    return failure(["unknown status: #{doc["status"].inspect}"]) unless STATUSES.include?(status)

    missing = REQUIRED_FIELDS.fetch(status, []).reject { |key| present?(doc[key]) }
    return failure(["status #{status} requires #{missing.join(', ')}"]) if missing.any?

    proposed_nodes, node_errors = normalize_proposed_nodes(doc["proposed_nodes"])
    return failure(node_errors) if node_errors.any?

    proposed_edges, edge_errors = normalize_proposed_edges(doc["proposed_edges"])
    return failure(edge_errors) if edge_errors.any?

    Result.new(
      ok: true,
      node: doc["node"].to_s,
      status: status,
      commit: doc["commit"],
      summary: doc["summary"],
      findings: normalize_findings(doc["findings"]),
      proposed_nodes: proposed_nodes,
      proposed_edges: proposed_edges,
      question: doc["question"],
      reason: doc["reason"],
      errors: [],
    )
  end

  def safe_load(text)
    { ok: true, value: YAML.safe_load(text, aliases: false, permitted_classes: []) }
  rescue Psych::Exception, Psych::AliasesNotEnabled, ArgumentError => e
    { ok: false, error: "return is not valid YAML: #{e.message}" }
  end
  private_class_method :safe_load

  def failure(errors)
    Result.new(
      ok: false, node: nil, status: nil, commit: nil, summary: nil, findings: [],
      proposed_nodes: [], proposed_edges: [], question: nil, reason: nil,
      errors: Array(errors)
    )
  end
  private_class_method :failure

  def present?(value)
    !(value.nil? || value.to_s.strip.empty?)
  end
  private_class_method :present?

  def stringify_keys(hash)
    hash.each_with_object({}) { |(k, v), memo| memo[k.to_s] = v }
  end
  private_class_method :stringify_keys

  # [entries_or_nil, errors]. `raw` absent is an empty, valid list (no
  # proposals is the common case). Anything present that is not an Array, or
  # any entry that is not a Hash carrying every PROPOSED_NODE_REQUIRED key,
  # refuses the whole return (row 4.37) rather than dropping the one bad
  # entry silently.
  def normalize_proposed_nodes(raw)
    return [[], []] if raw.nil?
    return [nil, ["proposed_nodes: must be a list, got #{raw.class}"]] unless raw.is_a?(Array)

    errors = []
    entries = raw.map do |entry|
      unless entry.is_a?(Hash)
        errors << "proposed_nodes entry must be a mapping, got #{entry.class}"
        next nil
      end

      e = stringify_keys(entry)
      missing = PROPOSED_NODE_REQUIRED.reject { |key| present?(e[key]) }
      if missing.any?
        errors << "proposed_nodes entry missing #{missing.join(', ')}"
        next nil
      end

      { "kind" => e["kind"], "title" => e["title"], "needs" => Array(e["needs"]),
        "files" => e["files"], "budget" => e["budget"] }
    end

    errors.any? ? [nil, errors] : [entries, []]
  end
  private_class_method :normalize_proposed_nodes

  # Same shape as #normalize_proposed_nodes, for proposed_edges (row 4.38):
  # each entry needs `from` and `to`.
  def normalize_proposed_edges(raw)
    return [[], []] if raw.nil?
    return [nil, ["proposed_edges: must be a list, got #{raw.class}"]] unless raw.is_a?(Array)

    errors = []
    entries = raw.map do |entry|
      unless entry.is_a?(Hash)
        errors << "proposed_edges entry must be a mapping, got #{entry.class}"
        next nil
      end

      e = stringify_keys(entry)
      missing = PROPOSED_EDGE_REQUIRED.reject { |key| present?(e[key]) }
      if missing.any?
        errors << "proposed_edges entry missing #{missing.join(', ')}"
        next nil
      end

      { "from" => e["from"], "to" => e["to"] }
    end

    errors.any? ? [nil, errors] : [entries, []]
  end
  private_class_method :normalize_proposed_edges

  # Coerce to an array of plain strings, capped at MAX_FINDINGS entries of at
  # most MAX_FINDING_LENGTH characters each (row 4.10) - a nested Hash, an
  # Integer, or any other scalar an executor emits becomes its #to_s rather
  # than reaching the Insight line RunnerAbsorb builds downstream.
  def normalize_findings(raw)
    return [] if raw.nil?

    list = raw.is_a?(Array) ? raw : [raw]
    list.first(MAX_FINDINGS).map { |item| item.to_s[0, MAX_FINDING_LENGTH] }
  end
  private_class_method :normalize_findings
end
