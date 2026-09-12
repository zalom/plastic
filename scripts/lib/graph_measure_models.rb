# encoding: UTF-8
# frozen_string_literal: true

require "json"
require "tmpdir"
require_relative "node_ledger"
require_relative "node_file"
require_relative "runner_policy"
require_relative "agent_models"

# GraphMeasureModels (intent 343, G10, n5): the store walk and the model
# comparison half of `graph-measure cohorts <store_dir>`. n6 adds the rates,
# the latency and the bar to the same verb; this module owns only the
# population, the qualified-field counts, and whether a recorded `model=`
# still matches what config resolves today.
#
# Read-only (spec D2): it opens every immediate child of `store_dir`, reads
# its `savepoint.md` and its `nodes/*.md`, and writes nothing. A store with
# no directories at all, an intent with no savepoint.md, and an intent
# directory this process cannot read all resolve to a counted, named
# exclusion rather than an exception (spec D4).
#
# D16: the ledger records `model=` with no role field. The comparison goes
# through `RunnerPolicy.model_for(kind, config:)`, the one place that maps a
# node's kind to the role the runner actually dispatched it against - never
# a hand-rolled kind-to-role table, and never `AgentModels::TIER_DEFAULTS`
# directly, which carries no `plastic-advisor` entry at all (that agent is a
# consultation agent, never auto-dispatched). Adds no second parser:
# `NodeLedger` owns the transition-line format, `NodeFile` owns the kind
# envelope and the `KIND_PREFIX` fallback, `RunnerPolicy`/`AgentModels` own
# the model resolution and the config-override chain.
module GraphMeasureModels
  module_function

  SAVEPOINT_FILE = "savepoint.md"
  UNAVAILABLE = "unavailable"

  # A ledger-wide existence check (spec row 5.3): "does this savepoint.md
  # carry this marker anywhere", not a per-node parse. `DONE_LINE_RE` mirrors
  # the exact two-space stage-line shape every `Savepoint.append_*` writer
  # emits (spec D9's "223 Done lines" is counted this way against the real
  # store).
  DONE_LINE_RE = /(?:\A|\n)\S+ {2}Done {2}/.freeze
  RUNNING_HOLDER_RE = /running holder=/.freeze
  MODEL_FIELD_RE = /\bmodel=/.freeze
  HOP_FIELD_RE = /\bhop=/.freeze

  # The named kinds RunnerPolicy actually assigns a model role to (spec row
  # 5.9): "decision" carries `model_role: nil` (it is never dispatched with a
  # model at all) and is excluded here, the same way RunnerPolicy's own table
  # excludes it from ever needing one.
  MEASURED_KINDS = RunnerPolicy::KIND_TABLE.reject { |_, v| v[:model_role].nil? }.keys.freeze

  # {ok:, population:, qualified:, excluded_no_model:, node_rows:, drift:,
  # unmeasured_kinds:}. `project_config:`/`global_config:` are already-loaded
  # config hashes (the `agents.models` shape `AgentModels` reads), never read
  # from disk or ENV here (spec D2, this module's own DI convention): the
  # caller owns loading real config.yml files.
  def read(store_dir, project_config: {}, global_config: {})
    dir = File.expand_path(store_dir.to_s)
    config = config_for(project_config, global_config)

    population = { total: 0, with_savepoint: 0, without_savepoint: 0, unreadable: [] }
    qualified = { done: 0, running_holder: 0, model: 0, hop: 0 }
    excluded_no_model = []
    node_rows = []

    each_child_name(dir).each do |name|
      path = File.join(dir, name)
      next unless File.directory?(path)

      population[:total] += 1
      status, payload = read_savepoint(path)
      case status
      when :missing
        population[:without_savepoint] += 1
      when :unreadable
        population[:unreadable] << { id: name, reason: payload }
      when :ok
        population[:with_savepoint] += 1
        walk_intent(name, path, payload, config, qualified, excluded_no_model, node_rows)
      end
    end

    record = {
      ok: true,
      population: population,
      qualified: qualified,
      excluded_no_model: excluded_no_model,
      node_rows: node_rows,
      drift: build_drift(node_rows),
      unmeasured_kinds: unmeasured_kinds(node_rows),
    }
    deep_freeze(record)
  end

  # NEW-4 (v2 review, D22): the one code path both the `cohorts` verb
  # (scripts/graph-measure) and the doctor's re-qualification rule
  # (scripts/doctor.rb) call to name the project-scope agent config file for
  # a given store - the store's sibling `config.yml`, the file that actually
  # exists in the wild and shares the global config.yml schema
  # (`~/.plastic/projects/knowdb/config.yml` is a real example), never
  # `project.yml`, whose template carries no `agents:` key at all. Pure path
  # arithmetic; the caller still owns loading it (this module's own DI
  # convention above - `read` never touches disk or ENV itself).
  #
  # Reproduced by hand before this fix: `scripts/graph-measure:225` read
  # `<store>/../project.yml`, so a real `plastic-executor: opus` override
  # written to a store's sibling `config.yml` never reached the `cohorts`
  # verb's own model comparison, while `scripts/doctor.rb`'s
  # `model_requalification_checks` passed an empty project config on
  # purpose - two different silences over the same store, agreeing with
  # each other only by accident.
  def project_config_path(store_dir)
    File.join(File.dirname(store_dir.to_s), "config.yml")
  end

  # --- rendering ---------------------------------------------------------------

  def render_json(record)
    JSON.generate(model(record))
  end

  def render_text(record)
    m = model(record)
    lines = []
    lines.concat(population_block(m["population"]))
    lines << ""
    lines.concat(qualified_block(m["qualified"], m["population"]))
    lines << ""
    lines.concat(excluded_block(m["excluded_no_model"]))
    lines << ""
    lines.concat(drift_block(m["drift"]))
    lines << ""
    lines.concat(unmeasured_block(m["unmeasured_kinds"]))
    "#{lines.join("\n")}\n"
  end

  def model(record)
    {
      "population" => population_model(record[:population]),
      "qualified" => record[:qualified].transform_keys(&:to_s),
      "excluded_no_model" => record[:excluded_no_model],
      "drift" => drift_model(record[:drift]),
      "unmeasured_kinds" => record[:unmeasured_kinds],
    }
  end

  def population_model(p)
    {
      "total_intent_dirs" => p[:total],
      "with_savepoint" => p[:with_savepoint],
      "without_savepoint" => p[:without_savepoint],
      "unreadable" => p[:unreadable].map { |u| { "id" => u[:id], "reason" => u[:reason] } },
    }
  end
  private_class_method :population_model

  def drift_model(drift)
    {
      "executor" => Array(drift[:executor]).map { |r| drift_row_model(r) },
      "advisor" => Array(drift[:advisor]).map { |r| drift_row_model(r) },
    }
  end
  private_class_method :drift_model

  def drift_row_model(r)
    {
      "intent" => r[:intent],
      "node" => r[:node],
      "kind" => r[:kind].to_s,
      "kind_source" => r[:kind_source].to_s,
      "recorded" => r[:recorded],
      "expected" => r[:expected],
    }
  end
  private_class_method :drift_row_model

  def population_block(p)
    lines = ["== Population =="]
    lines << "intent directories: #{p['total_intent_dirs']}"
    lines << "with savepoint.md: #{p['with_savepoint']}"
    lines << "without savepoint.md (never started): #{p['without_savepoint']}"
    if p["unreadable"].empty?
      lines << "unreadable: 0"
    else
      lines << "unreadable: #{p['unreadable'].length}"
      p["unreadable"].each { |u| lines << "  #{u['id']}: #{u['reason']}" }
    end
    lines
  end
  private_class_method :population_block

  def qualified_block(q, p)
    [
      "== Qualified fields (of #{p['with_savepoint']} ledgers) ==",
      "Done line: #{q['done']}",
      "running holder=: #{q['running_holder']}",
      "model=: #{q['model']}",
      "hop=: #{q['hop']}",
    ]
  end
  private_class_method :qualified_block

  def excluded_block(excluded)
    lines = ["== Excluded (no model= anywhere) =="]
    if excluded.empty?
      lines << "(none)"
    else
      excluded.each { |id| lines << id }
    end
    lines
  end
  private_class_method :excluded_block

  def drift_block(drift)
    lines = ["== Model drift =="]
    if drift["executor"].empty? && drift["advisor"].empty?
      lines << "(none)"
      return lines
    end

    %w[executor advisor].each do |role|
      next if drift[role].empty?

      lines << "-- #{role} --"
      lines << "| Intent | Node | Kind | Kind source | Recorded | Expected |"
      lines << "| --- | --- | --- | --- | --- | --- |"
      drift[role].each do |r|
        lines << "| #{r['intent']} | #{r['node']} | #{r['kind']} | #{r['kind_source']} | #{r['recorded']} | #{r['expected']} |"
      end
    end
    lines
  end
  private_class_method :drift_block

  def unmeasured_block(kinds)
    lines = ["== Unmeasured kinds =="]
    lines << (kinds.empty? ? "(none)" : kinds.join(", "))
    lines
  end
  private_class_method :unmeasured_block

  # --- the store walk ------------------------------------------------------------

  def each_child_name(dir)
    return [] unless File.directory?(dir)

    Dir.children(dir).reject { |e| e.start_with?(".") }.sort
  rescue Errno::EACCES, Errno::ENOENT
    []
  end
  private_class_method :each_child_name

  # [:ok, content] | [:missing, nil] | [:unreadable, message]. `File.exist?`
  # silently returns false for a permission-denied path (it never raises), so
  # a chmod-000 intent directory would otherwise misreport as "never
  # started" (row 5.2) rather than "unreadable" (row 5.13) - reading the
  # file directly and catching the two errnos separately is what tells the
  # two cases apart.
  def read_savepoint(intent_dir)
    content = File.read(File.join(intent_dir, SAVEPOINT_FILE))
    [:ok, content.scrub]
  rescue Errno::ENOENT
    [:missing, nil]
  rescue Errno::EACCES => e
    [:unreadable, e.message]
  end
  private_class_method :read_savepoint

  def walk_intent(name, path, content, config, qualified, excluded_no_model, node_rows)
    qualified[:done] += 1 if content.match?(DONE_LINE_RE)
    qualified[:running_holder] += 1 if content.match?(RUNNING_HOLDER_RE)
    qualified[:hop] += 1 if content.match?(HOP_FIELD_RE)

    unless content.match?(MODEL_FIELD_RE)
      excluded_no_model << name
      return
    end
    qualified[:model] += 1

    entries = NodeLedger.entries_from_content(content).reject { |e| e[:torn] }
    entries.group_by { |e| e[:subject] }.each do |subject, subject_entries|
      recorded = recorded_model(subject_entries)
      next unless present?(recorded)

      kind, kind_source = resolve_kind(path, subject)
      role = RunnerPolicy.policy_for(kind)[:model_role]
      next unless role

      expected = RunnerPolicy.model_for(kind, config: config)
      node_rows << { intent: name, node: subject, kind: kind, kind_source: kind_source,
                      role: role, recorded: recorded, expected: expected }
    end
  end
  private_class_method :walk_intent

  # The last (file-order) transition line for `subject` that carries a
  # `model=`, mirroring GraphMeasure's own "most recent field wins" reading
  # (spec row 1.25's shape, reused here rather than re-derived).
  def recorded_model(subject_entries)
    subject_entries.reverse_each do |e|
      value = e[:fields]["model"]
      return value if present?(value)
    end
    nil
  end
  private_class_method :recorded_model

  # --- config chain: spec row 5.6 -------------------------------------------------

  # Project override, then global override, then RunnerPolicy's own shipped
  # default (spec D16, row 5.6): `AgentModels.override_map` already encodes
  # that precedence (global overlaid by project, project wins), so this
  # module adds no second merge rule - it only re-wraps the flat map back
  # into the `agents.models` shape `RunnerPolicy.model_for` reads.
  def config_for(project_config, global_config)
    merged = AgentModels.override_map(project_config: project_config, global_config: global_config)
    { "agents" => { "models" => merged } }
  end
  private_class_method :config_for

  # --- kind resolution: spec D6, row 5.11 ------------------------------------------

  # Kind from the node file when one exists; otherwise `NodeFile::KIND_PREFIX`,
  # flagged (spec row 5.11). `GraphMeasure.resolve_kind` already does exactly
  # this, but it is `private_class_method` (carried from n1: reuse the local
  # equivalent, or define one in this module - never reopen another module to
  # make its private method public), so this is this module's own copy over
  # the same public `NodeFile` API.
  # B6 (v1 review): NodeFile.parse reads its own path and does not scrub, so
  # one bad byte anywhere under nodes/*.md raised out of it and took the
  # whole `cohorts` verb down with it - reproduced by appending an invalid
  # UTF-8 byte to a copy of 340's nodes/n1.md: `cohorts` exited 1 with
  # "internal error: invalid byte sequence in UTF-8" (via this module's own
  # store walk, since `cohorts` calls `GraphMeasureModels.read` for its
  # model-comparison half), the same failure `budget` hit through its own
  # direct `NodeFile.parse` call. `GraphMeasure.with_safe_path` already
  # solves this; it is `private_class_method` (carried from n1), so this is
  # a local copy, the same shape `resolve_kind` and `present?` already are
  # in this module, never a reopen.
  def resolve_kind(intent_dir, id)
    path = find_node_file(intent_dir, id)
    if path
      parsed = with_safe_path(path) { |p| p ? NodeFile.parse(p) : nil }
      return [parsed[:kind], :node_file] if parsed && parsed[:kind] && !parsed[:kind].to_s.empty?
    end

    prefix = id.to_s[/\A[a-z]{1,2}/]
    kind = prefix && NodeFile::KIND_PREFIX.invert[prefix]
    [kind, :fallback]
  end
  private_class_method :resolve_kind

  def find_node_file(intent_dir, id)
    Dir.glob(File.join(intent_dir, "nodes", "*.md")).find do |f|
      NodeFile.filename_matches_id?(File.basename(f, ".md"), id)
    end
  end
  private_class_method :find_node_file

  def with_safe_path(path)
    return yield(nil) unless path && File.exist?(path)

    raw = File.read(path)
    scrubbed = raw.scrub
    return yield(path) if scrubbed == raw

    Dir.mktmpdir("graph-measure-models-scrub") do |tmp|
      safe_path = File.join(tmp, File.basename(path))
      File.write(safe_path, scrubbed)
      yield(safe_path)
    end
  end
  private_class_method :with_safe_path

  # --- drift and unmeasured kinds: spec rows 5.7, 5.9 ------------------------------

  def build_drift(node_rows)
    executor = node_rows.select { |r| r[:role] == :executor && r[:recorded] != r[:expected] }
    advisor = node_rows.select { |r| r[:role] == :advisor && r[:recorded] != r[:expected] }
    { executor: executor, advisor: advisor }
  end
  private_class_method :build_drift

  def unmeasured_kinds(node_rows)
    present_kinds = node_rows.map { |r| r[:kind] }.compact.uniq
    MEASURED_KINDS.reject { |k| present_kinds.include?(k) }
  end
  private_class_method :unmeasured_kinds

  # --- shared helpers ---------------------------------------------------------------

  # NodeLedger.present? is private_class_method (carried from n1): this is
  # the local equivalent, not a reopen.
  def present?(value)
    !(value.nil? || value.to_s.strip.empty?)
  end
  private_class_method :present?

  def deep_freeze(obj)
    case obj
    when Hash
      obj.each { |k, v| deep_freeze(k); deep_freeze(v) }
    when Array
      obj.each { |v| deep_freeze(v) }
    end
    obj.freeze
  end
  private_class_method :deep_freeze
end
