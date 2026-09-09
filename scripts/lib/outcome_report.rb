# encoding: UTF-8
# frozen_string_literal: true

require "yaml"
require "date"
require_relative "graph_file"
require_relative "node_file"
require_relative "node_ledger"
require_relative "atomic_write"

# OutcomeReport (intent 339, G6): the report model over graph.md, nodes/, and
# the node ledger (n1), the generator and its command (n2), the plan-versus-
# delivered diff and the transitive stale walk (n3), and findings, read and
# capped (n4). Every rendered cell traces to graph.md, a node file, or a
# ledger line; an absent source renders as a named reason, never a guess
# (spec D1). Pure: no clock, no environment, every path an explicit argument.
# Edges come from GraphFile/GraphEdges only - never the older node-ledger
# reader intent 336 deletes in this same batch (spec D16).
module OutcomeReport
  module_function

  # One past NodeFile::KIND_PREFIX ("n" => "work", ...), so a declared node
  # with no node file on disk (matrix 1.8) still gets a kind, inferred from
  # its id's own prefix rather than left nil.
  KIND_BY_PREFIX = NodeFile::KIND_PREFIX.invert.freeze

  TITLE_LINE_RE = /\A#\s+\S+\s*-\s*(.+)\z/.freeze

  # {ok:, errors:, goal:, edges:, nodes:, entries:}. `edges` maps a declared
  # node id to the ids it needs (GraphEdges' own shape). `nodes` maps every id
  # this intent has ever mentioned - declared in graph.md, filed under
  # nodes/, or named in the ledger - to {declared:, file_present:, kind:,
  # title:, state:, fields:, retries:}. `entries` is the raw ledger read
  # (NodeLedger.entries' own shape), carried through so #graph_diff and
  # #stale_nodes can walk file order without a second read. Never raises
  # across its boundary (matrix 1.1, 1.6).
  def model(intent_dir)
    graph_path = File.join(intent_dir, "graph.md")
    unless File.exist?(graph_path)
      return { ok: false, errors: ["no graph.md at #{graph_path}"], goal: nil, edges: {}, nodes: {}, entries: [] }
    end

    parsed = GraphFile.parse(graph_path)
    edges = (parsed[:graph] && parsed[:graph][:edges]) || {}
    declared_ids = (parsed[:graph] && parsed[:graph][:nodes]) || []

    ledger_path = File.join(intent_dir, "savepoint.md")
    entries = NodeLedger.entries(ledger_path)
    ledger_ids = entries.map { |e| e[:subject] }.uniq
    file_ids = node_file_ids(intent_dir)

    all_ids = (declared_ids + ledger_ids + file_ids).uniq
    nodes = all_ids.each_with_object({}) do |id, memo|
      memo[id] = node_entry(intent_dir, id, declared_ids, entries)
    end

    { ok: parsed[:ok], errors: parsed[:errors] || [], goal: parsed[:goal], edges: edges, nodes: nodes,
      entries: entries }
  rescue StandardError => e
    { ok: false, errors: ["outcome report model crashed: #{e.message}"], goal: nil, edges: {}, nodes: {}, entries: [] }
  end

  def node_file_ids(intent_dir)
    Dir.glob(File.join(intent_dir, "nodes", "*.md")).sort.filter_map do |path|
      NodeFile.parse(path)[:node]
    end
  end

  def node_file_path_for(intent_dir, id)
    Dir.glob(File.join(intent_dir, "nodes", "*.md")).sort.find do |path|
      NodeFile.parse(path)[:node] == id
    end
  end

  def node_entry(intent_dir, id, declared_ids, entries)
    file_path = node_file_path_for(intent_dir, id)
    parsed = file_path ? NodeFile.parse(file_path) : nil
    kind = (parsed && parsed[:kind]) || KIND_BY_PREFIX[id.to_s[0]]
    title = (parsed && title_from_body(parsed[:body])) || id.to_s

    subject_entries = entries.select { |e| e[:subject] == id }
    non_torn = subject_entries.reject { |e| e[:torn] }
    state = non_torn.empty? ? "planned" : NodeLedger.resolved_state(non_torn.last[:state])
    done_entry = non_torn.select { |e| e[:state] == "done" }.last
    fields = done_entry ? done_entry[:fields] : {}
    retries = non_torn.count { |e| e[:state] == "failed_verification" }

    {
      declared: declared_ids.include?(id),
      file_present: !file_path.nil?,
      kind: kind,
      title: title,
      state: state,
      fields: fields,
      retries: retries,
    }
  end

  def title_from_body(body)
    return nil unless body

    line = body.to_s.each_line.find { |l| l.start_with?("#") }
    return nil unless line

    m = line.strip.match(TITLE_LINE_RE)
    m && m[1].strip
  end

  # --- n2: the generator -------------------------------------------------------

  PLACEHOLDER_SUMMARY = "(what was delivered)"
  NON_EVIDENCE_FIELD_KEYS = %w[holder expires packet model gates commit verdict reason question by expired suite].freeze

  # D14: a pipe in any generated table cell (or bullet line) is replaced with a
  # forward slash, never escaped - ReportScreen.table_rows splits on the bare
  # character with no escape awareness.
  def sanitize_cell(text)
    text.to_s.gsub("|", "/")
  end

  # Numeric-aware id sort ("n2" before "n10"), for deterministic output order
  # regardless of Hash insertion order.
  def sort_ids(ids)
    ids.sort_by do |id|
      m = id.to_s.match(/\A([A-Za-z]+)(\d+)\z/)
      m ? [m[1], m[2].to_i] : [id.to_s, 0]
    end
  end

  def section_body(text, heading)
    return nil unless text

    text.split(/^#{Regexp.escape(heading)}\s*$/, 2)[1]&.split(/^## /, 2)&.first
  end

  def existing_frontmatter(text)
    return {} unless text && text.start_with?("---")

    parts = text.split("---", 3)
    return {} if parts.length < 3

    (YAML.safe_load(parts[1], permitted_classes: [Date, Time]) || {}).each_with_object({}) do |(k, v), memo|
      memo[k.to_s] = v
    end
  rescue StandardError
    {}
  end

  # An authored block, trimmed, or nil when the section is absent, blank, or
  # still the literal "None"/placeholder scaffold text (spec D2).
  def preserved_block(existing_text, heading, placeholder: nil)
    body = section_body(existing_text, heading)
    return nil if body.nil?

    trimmed = body.gsub(/<!--.*?-->/m, "").strip
    return nil if trimmed.empty? || trimmed == "None"
    return nil if placeholder && trimmed == placeholder

    body.strip
  end

  def default_summary(model)
    work = model[:nodes].select { |_, n| n[:kind] == "work" }
    done = work.select { |_, n| n[:state] == "done" }
    "#{done.length} of #{work.length} work node#{work.length == 1 ? '' : 's'} delivered."
  end

  def title_text(model)
    goal = model[:goal].to_s.strip
    return "generated report" if goal.empty?

    goal.each_line.first.to_s.strip
  end

  def render_delivered_section(model)
    rows = model[:nodes].select { |_, n| n[:kind] == "work" && n[:state] == "done" }
    lines = ["## Delivered", "| Row | What |", "| --- | --- |"]
    sort_ids(rows.keys).each { |id| lines << "| #{id} | #{sanitize_cell(rows[id][:title])} |" }
    "#{lines.join("\n")}\n"
  end

  def verification_line_for(id, node)
    fields = node[:fields] || {}
    return "- #{id}: verification failed (#{sanitize_cell(fields['reason'] || 'reason not recorded')})" if node[:state] == "failed_verification"

    parts = []
    parts << "tests committed red before `#{sanitize_cell(fields['commit'])}`" if fields["commit"]
    parts << "gates=#{sanitize_cell(fields['gates'])}" if fields["gates"]
    parts << "verdict=#{sanitize_cell(fields['verdict'])}" if fields["verdict"]
    extra = fields.reject { |k, _| NON_EVIDENCE_FIELD_KEYS.include?(k) }
    extra.each { |k, v| parts << "#{k}=#{sanitize_cell(v)}" }
    parts << "retried #{node[:retries]}x" if node[:retries].to_i.positive?
    return nil if parts.empty?

    "- #{id}: #{parts.join(', ')}"
  end

  def render_verification_section(model)
    candidates = model[:nodes].select { |_, n| %w[work verify].include?(n[:kind]) }
    lines = sort_ids(candidates.keys).filter_map { |id| verification_line_for(id, candidates[id]) }

    suite = candidates.values.filter_map { |n| n[:fields] && n[:fields]["suite"] }.first
    lines << "- suite: #{suite}" if suite

    lines = ["- no work or verify node has recorded evidence yet"] if lines.empty?
    "## Verification\n#{lines.join("\n")}\n"
  end

  def render_needs_you_default(model)
    needs = model[:nodes].select { |_, n| n[:state] == "needs_decision" }
    return "None" if needs.empty?

    lines = ["| N | Need | Reason |", "| --- | --- | --- |"]
    sort_ids(needs.keys).each_with_index do |id, i|
      reason = (needs[id][:fields] && needs[id][:fields]["question"]) || "not recorded"
      lines << "| N#{i + 1} | #{sanitize_cell(id)} | #{sanitize_cell(reason)} |"
    end
    lines.join("\n")
  end

  # {ok:, errors:, goal:, edges:, nodes:} in, the whole `outcome.md` text out.
  # Preserved verbatim when authored (spec D2): every frontmatter key except
  # `disposition`, `## Summary`, `## Needs you`, `## Follow-ups`. Regenerated
  # every time: `## Delivered`, `## Verification` (and, once n3/n4 wire them
  # in, `## Graph diff` and `## Findings`).
  def render(model, disposition:, existing: nil, findings: [])
    fm = existing_frontmatter(existing)
    fm["disposition"] = disposition
    fm_lines = ["---"] + fm.map { |k, v| "#{k}: #{v}" } + ["---"]

    summary = preserved_block(existing, "## Summary", placeholder: PLACEHOLDER_SUMMARY) || default_summary(model)
    needs_you = preserved_block(existing, "## Needs you") || render_needs_you_default(model)
    follow_ups = preserved_block(existing, "## Follow-ups") || "None"

    lines = fm_lines.dup
    lines << "# Outcome: #{title_text(model)}"
    lines << ""
    lines << "## Summary"
    lines << summary
    lines << ""
    lines << render_delivered_section(model)
    lines << render_verification_section(model)
    lines << graph_diff(model)
    lines << render_findings_section(findings) unless findings.nil? || findings.empty?
    lines << "## Needs you"
    lines << needs_you
    lines << ""
    lines << "## Follow-ups"
    lines << follow_ups
    "#{lines.join("\n")}\n"
  end

  # --- n3: plan versus delivered, and stale -----------------------------------

  # A done node's transitive `needs` closure (spec D5), by ledger LINE
  # POSITION, never timestamp - the ledger's own status rule is last line per
  # subject in file order, so a flag computed from anything else could
  # disagree with the state printed beside it. `stale_fn:` (spec D6) lets
  # intent 336's ready-set module supply its own computation without an edit
  # here. Cycle-guarded: a node already on the current walk's path is never
  # re-entered.
  def stale_nodes(entries:, edges:, stale_fn: nil)
    return stale_fn.call(entries: entries, edges: edges) if stale_fn

    non_torn = entries.reject { |e| e[:torn] }
    last_state = {}
    last_index = {}
    done_index = {}
    non_torn.each_with_index do |e, i|
      last_state[e[:subject]] = e[:state]
      last_index[e[:subject]] = i
      done_index[e[:subject]] = i if e[:state] == "done"
    end

    edges.keys.select do |id|
      done_index.key?(id) && stale_via_closure?(id, edges, last_state, last_index, done_index[id], [])
    end
  end

  def stale_via_closure?(id, edges, last_state, last_index, own_done_idx, visiting)
    return false if visiting.include?(id)

    visiting = visiting + [id]
    (edges[id] || []).any? do |dep|
      (last_state[dep] == "superseded" && last_index[dep] && last_index[dep] > own_done_idx) ||
        stale_via_closure?(dep, edges, last_state, last_index, own_done_idx, visiting)
    end
  end

  # The plan-versus-delivered divergence: a planned node not done, a node the
  # ledger knows that the graph never declared, a node that took a retry, a
  # stale node (spec D4). One line saying so when nothing diverged.
  def graph_diff(model)
    lines = []

    declared = model[:nodes].select { |_, n| n[:declared] }
    sort_ids(declared.keys).each do |id|
      lines << "#{id} is #{declared[id][:state]}, not done" unless declared[id][:state] == "done"
    end

    undeclared = model[:nodes].reject { |_, n| n[:declared] }
    sort_ids(undeclared.keys).each { |id| lines << "#{id} was not declared in graph.md" }

    retried = model[:nodes].select { |_, n| n[:retries].to_i.positive? }
    sort_ids(retried.keys).each do |id|
      n = retried[id]
      lines << "#{id} took #{n[:retries]} #{n[:retries] == 1 ? 'retry' : 'retries'}"
    end

    stale = stale_nodes(entries: model[:entries] || [], edges: model[:edges] || {})
    sort_ids(stale).each { |id| lines << "#{id} is stale: a dependency was superseded after it finished" }

    return "## Graph diff\nDelivered matches the plan.\n" if lines.empty?

    "## Graph diff\n#{lines.map { |l| "- #{l}" }.join("\n")}\n"
  end

  # --- n4: findings, read and capped ------------------------------------------

  # Two lines at the screens' own 115-column limit (spec D15). A named
  # constant so the number is never folded into a regex.
  FINDING_CAP = 200

  # `### Findings` under the intent record's own `## Insights` section (spec
  # D7). G7 writes those lines one Insight entry at a time; nothing writes one
  # today, so this reads a fixture shape until then. [] when the record, the
  # `## Insights` section, or the `### Findings` subsection is absent -
  # never raises, never treats the whole Insights section as one finding.
  def findings(intent_dir)
    path = File.join(intent_dir, "#{File.basename(intent_dir)}.md")
    return [] unless File.exist?(path)

    text = File.read(path)
    insights = text.split(/^## Insights\s*$/, 2)[1].to_s.split(/^## /, 2)[0].to_s
    body = insights.split(/^### Findings\s*$/, 2)[1]
    return [] if body.nil?

    body = body.split(/^#+\s/, 2)[0]
    finding_bullet_rows(body).map { |f| cap_finding(sanitize_cell(f)) }
  end

  # Same continuation-line rule as ReportScreen.bullet_rows: a "- " line plus
  # its wrapped continuation, ending at a blank line or the next heading.
  def finding_bullet_rows(section)
    rows = []
    section.to_s.each_line do |line|
      stripped = line.strip
      if line.lstrip.start_with?("- ")
        rows << line.lstrip.sub(/\A-\s*/, "").strip
      elsif stripped.empty? || line.start_with?("#")
        rows << nil unless rows.empty? || rows.last.nil?
      elsif !rows.empty? && !rows.last.nil?
        rows[rows.length - 1] = "#{rows.last} #{stripped}"
      end
    end
    rows.compact
  end

  def cap_finding(text)
    return text if text.length <= FINDING_CAP

    "#{text[0...(FINDING_CAP - 3)].rstrip}..."
  end

  def render_findings_section(findings)
    return "" if findings.nil? || findings.empty?

    lines = ["## Findings", "| Finding |", "| --- |"]
    findings.each { |f| lines << "| #{f} |" }
    "#{lines.join("\n")}\n"
  end

  def write(intent_dir, disposition:, renamer: File.method(:rename))
    outcome_path = File.join(intent_dir, "outcome.md")
    existing = File.exist?(outcome_path) ? File.read(outcome_path) : nil
    m = model(intent_dir)
    text = render(m, disposition: disposition, existing: existing, findings: findings(intent_dir))
    AtomicWrite.write(outcome_path, text, renamer: renamer)
    text
  end
end
