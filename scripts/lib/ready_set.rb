# encoding: UTF-8
# frozen_string_literal: true

require_relative "graph_file"
require_relative "graph_edges"
require_relative "node_file"
require_relative "node_ledger"

# ReadySet (intent 336, G3): the one function that says what may run next.
# A node is ready when four conditions all hold: its own state is eligible,
# every need is done under an attributed non-torn line, no file-overlapping
# sibling is currently running, and its dispatch attempts are under its
# kind's cap. Every failed condition contributes a named blocker. Batches are
# the topological layers of the edge set; the critical path is every
# maximal-length chain, counted in nodes.
#
# Pure and dependency-injected: #ready? takes already-parsed values (content,
# graph, nodes) and touches no filesystem at all, because the authoritative
# call runs inside GuardedAppend's lock hold against the exact bytes the
# guard read - a second, unguarded re-read there would buy nothing. #analyze
# is the disk-reading counterpart every other caller uses. This module reads
# no environment variable and knows nothing about the cross-intent knowledge
# graph an intent's own frontmatter carries; that field is deliberately never
# named here (327 D40).
module ReadySet
  module_function

  # D3: retry caps by kind, counted as dispatch attempts (running lines since
  # the subject's last terminal line), not failures. Injectable via `caps:`
  # so a caller overrides the policy without editing this module.
  DEFAULT_CAPS = { "work" => 3, "verify" => 3, "research" => 2, "decision" => 2 }.freeze

  # D9: a fan-in graph has exponentially many maximal-length paths; this
  # bounds how many are ever materialized, with the true total reported
  # beside them via a separate polynomial count.
  DEFAULT_MAX_PATHS = 16

  # A written state's resolved status is eligible for "running" (D1's
  # condition 1) only for these two: `reclaimed` already resolves to
  # `planned` through NodeLedger::RESOLUTION, and `failed_verification` is
  # deliberately eligible too, so the retry C3 requires is representable.
  READY_PRIOR_STATES = %w[planned failed_verification].freeze

  TERMINAL_STATES = %w[done superseded abandoned].freeze

  # The fixed key list a ranker row ever carries (D11/C16): every key is
  # state- or edge-derived, never a telemetry field (tokens, wall, model,
  # suite, packet). Pinned by test/ready_set_ranker_test.rb.
  ROW_KEYS = %i[id kind batch retry downstream_hops on_critical_path].freeze

  # --- the readiness decision (D1) ---------------------------------------------

  # ready?(content:, subject:, graph:, nodes:, caps:) -> {ready:, blockers:}.
  # `graph` carries {edges: {id => [needs...]}}; `nodes` carries
  # {id => {kind:, files:}}. Touches no filesystem; every fact it needs is a
  # value already passed in, so it can be called again after the intent
  # directory backing those values has been deleted.
  def ready?(content:, subject:, graph:, nodes:, caps: DEFAULT_CAPS, now: Time.now)
    blockers = []
    status_map = NodeLedger.status_from_content(content)
    entries = NodeLedger.entries_from_content(content)

    own_status = status_map.fetch(subject.to_s, "planned")
    unless READY_PRIOR_STATES.include?(own_status)
      blockers << "#{subject} is #{own_status}, not eligible to enter running"
    end

    own_decl = nodes[subject.to_s] || {}
    # Finding 1b: a node graph.md declares with no readable nodes/ file
    # (missing, or a malformed envelope) carries this from load_graph and is
    # never ready, regardless of what the other three conditions say.
    blockers << own_decl[:file_error] if own_decl[:file_error]

    edges = (graph || {})[:edges] || {}
    needs = edges[subject.to_s] || []
    needs.each do |target|
      last = entries.select { |e| !e[:torn] && e[:subject] == target }.last
      unless last && last[:state] == "done" && NodeLedger.attributed?(last)
        blockers << "needs target #{target} has no attributed, well-formed done line"
      end
    end

    if dead_end?(subject.to_s, edges, status_map)
      blockers << "#{subject} is a dead end: a needed node is superseded or abandoned"
    end

    own_files = normalize_files(own_decl[:files])
    if own_files.any?
      overlapping = (nodes.keys - [subject.to_s]).select do |other|
        other_files = normalize_files((nodes[other] || {})[:files])
        next false if other_files.empty?
        next false unless status_map.fetch(other, "planned") == "running"

        (own_files & other_files).any?
      end
      if overlapping.any?
        blockers << "file overlap with running sibling(s): #{overlapping.sort.join(', ')}"
      end
    end

    # Finding 1a: an unknown or nil kind (a node the graph never declared,
    # or one whose file could not be read) must never fall through to no
    # cap at all - it gets the work cap, the widest of the four, rather
    # than being skipped or refused outright. Preserves 335's shipped
    # legacy path: no graph.md at all means an empty nodes map and a nil
    # kind, which must keep dispatching, bounded by this fallback cap.
    kind = own_decl[:kind]
    caps_table = caps || DEFAULT_CAPS
    cap = caps_table.fetch(kind) { caps_table["work"] }
    if cap
      attempts = attempts_count(entries, subject.to_s)
      blockers << "#{subject} is at its dispatch cap (#{attempts}/#{cap})" if attempts >= cap
    end

    { ready: blockers.empty?, blockers: blockers }
  end

  def normalize_file(f)
    f.to_s.sub(%r{\A\./}, "").sub(%r{/\z}, "")
  end

  def normalize_files(files)
    (files || []).map { |f| normalize_file(f) }
  end

  # D3: the `running` lines for `subject` since its last `done`, `superseded`
  # or `abandoned` line, or from the start of the ledger when it has none.
  def attempts_count(entries, subject)
    own = entries.select { |e| !e[:torn] && e[:subject] == subject }
    last_terminal = own.rindex { |e| TERMINAL_STATES.include?(e[:state]) }
    after = last_terminal ? own[(last_terminal + 1)..-1] : own
    after.count { |e| e[:state] == "running" }
  end

  # D5: every non-torn failed_verification line for subject in the whole
  # ledger. Never resets, and never drives the cap (D3's attempt count does).
  def failed_verification_count(entries, subject)
    entries.count { |e| !e[:torn] && e[:subject] == subject && e[:state] == "failed_verification" }
  end

  # D7: subject is a dead end when any of its needs targets, directly or
  # transitively, resolves to superseded or abandoned.
  def dead_end?(subject, edges, status_map, memo = {})
    return memo[subject] if memo.key?(subject)

    memo[subject] = false
    needs = edges[subject] || []
    result = needs.any? do |target|
      %w[superseded abandoned].include?(status_map.fetch(target, "planned")) ||
        dead_end?(target, edges, status_map, memo)
    end
    memo[subject] = result
  end

  # D8: a done node is stale when, at the end of the ledger, one of its needs
  # resolves to superseded or abandoned AND the line that put it there comes
  # later in file order than the node's own done line.
  def stale?(entries, subject, edges, status_map)
    return false unless status_map[subject] == "done"

    own_done_idx = entries.each_index.select do |i|
      !entries[i][:torn] && entries[i][:subject] == subject && entries[i][:state] == "done"
    end.last
    return false unless own_done_idx

    needs = edges[subject] || []
    needs.any? do |target|
      target_idx = entries.each_index.select { |i| !entries[i][:torn] && entries[i][:subject] == target }.last
      next false unless target_idx

      %w[superseded abandoned].include?(entries[target_idx][:state]) && target_idx > own_done_idx
    end
  end

  # --- the disk-reading counterpart --------------------------------------------

  # load_graph(intent_dir) -> {ok:, edges:, nodes:, errors:}. The parse-once
  # step every caller (analyze, node-transition, the roadmap frontier, the
  # doctor rule) shares: graph.md through GraphFile (the one parser), each
  # declared node's kind and files through NodeFile. Never raises: a missing
  # or invalid graph.md, a cyclic graph, a malformed node file, or a node the
  # graph declares with no file all become `ok: false` or an `errors` entry,
  # never an exception across the boundary.
  def load_graph(intent_dir)
    graph_path = File.join(intent_dir, "graph.md")
    parsed = GraphFile.parse(graph_path)
    if parsed[:graph].nil?
      errors = parsed[:errors].empty? ? ["missing or invalid graph.md at #{graph_path}"] : parsed[:errors]
      return { ok: false, edges: {}, nodes: {}, errors: errors }
    end

    edges = parsed[:graph][:edges]
    errors = parsed[:graph][:errors].dup

    cyc = GraphEdges.cycle(edges)
    if cyc
      return { ok: false, edges: edges, nodes: {},
                errors: errors + ["cyclic graph, cannot compute readiness: #{cyc.join(' > ')}"] }
    end

    nodes = {}
    parsed[:graph][:nodes].each do |id|
      path = find_node_path(intent_dir, id)
      if path.nil?
        msg = "node #{id.inspect} is declared in graph.md but has no nodes/ file"
        errors << msg
        nodes[id] = { kind: nil, files: [], file_error: msg }
        next
      end

      nf = NodeFile.parse(path)
      if nf[:ok]
        nodes[id] = { kind: nf[:kind], files: nf[:files] || [] }
      else
        msg = "node #{id.inspect}'s file is malformed: #{nf[:errors].join('; ')}"
        errors << msg
        nodes[id] = { kind: nil, files: [], file_error: msg }
      end
    end

    { ok: true, edges: edges, nodes: nodes, errors: errors }
  end

  # analyze(intent_dir, now:, caps:, max_paths:, ranker:) -> a Result hash
  # over the whole graph: per-node view, batches, critical path(s), and the
  # ranked ready order. Never raises across the boundary: everything
  # #load_graph reports becomes an entry in `errors`, and analysis continues
  # for every node it still can.
  def analyze(intent_dir, now: Time.now, caps: DEFAULT_CAPS, max_paths: DEFAULT_MAX_PATHS, ranker: nil)
    ranker ||= FinishFirstRanker.new
    loaded = load_graph(intent_dir)
    return error_result(loaded[:errors]) unless loaded[:ok]

    edges = loaded[:edges]
    nodes = loaded[:nodes]
    errors = loaded[:errors]

    savepoint_path = File.join(intent_dir, "savepoint.md")
    content = File.exist?(savepoint_path) ? File.read(savepoint_path) : ""

    views = build_node_views(content: content, edges: edges, nodes: nodes, caps: caps)

    batch_result = batches(edges)
    path_result = critical_paths(edges, max_paths: max_paths)

    rows = ready_rows(views, batch_result, path_result)
    ranked = ranker.rank(rows)

    {
      ok: true,
      errors: errors,
      nodes: views,
      batches: batch_result[:ok] ? batch_result[:batches] : [],
      batches_error: batch_result[:ok] ? nil : batch_result[:error],
      critical_path: path_result[:ok] ? path_result[:critical_path] : nil,
      paths: path_result[:ok] ? path_result[:paths] : [],
      hops: path_result[:ok] ? path_result[:hops] : 0,
      max_paths_total: path_result[:ok] ? path_result[:total] : 0,
      ranked_ready: ranked,
      ranker_name: ranker.name,
    }
  end

  def error_result(errors)
    {
      ok: false, errors: errors, nodes: {}, batches: [], batches_error: nil, critical_path: nil,
      paths: [], hops: 0, max_paths_total: 0, ranked_ready: [], ranker_name: nil,
    }
  end

  def find_node_path(intent_dir, id)
    Dir.glob(File.join(intent_dir, "nodes", "#{id}*.md")).sort.find do |f|
      NodeFile.filename_matches_id?(File.basename(f, ".md"), id)
    end
  end

  def build_node_views(content:, edges:, nodes:, caps:)
    status_map = NodeLedger.status_from_content(content)
    entries = NodeLedger.entries_from_content(content)
    dead_memo = {}

    nodes.each_with_object({}) do |(id, decl), views|
      state = status_map.fetch(id, "planned")
      r = ready?(content: content, subject: id, graph: { edges: edges }, nodes: nodes, caps: caps)
      views[id] = {
        kind: decl[:kind],
        files: decl[:files] || [],
        state: state,
        attempts: attempts_count(entries, id),
        cap: (caps || DEFAULT_CAPS)[decl[:kind]],
        failed_verification_count: failed_verification_count(entries, id),
        ready: r[:ready],
        blockers: r[:blockers],
        dead_end: dead_end?(id, edges, status_map, dead_memo),
        stale: stale?(entries, id, edges, status_map),
      }
    end
  end

  # --- n3: batches and the critical path ---------------------------------------

  def all_nodes(edges)
    nodes = edges.keys.dup
    edges.each_value { |targets| (targets || []).each { |t| nodes << t unless nodes.include?(t) } }
    nodes
  end

  # Topological layers of `edges`: layer one is every node needing nothing,
  # layer k is every node all of whose needs sit in layers below k. Structural
  # only, computed from edges alone, never from ledger state (D-something in
  # the spec: "a batch that shrinks as nodes finish is a ready set, not a
  # batch").
  def batches(edges)
    cyc = GraphEdges.cycle(edges)
    return { ok: false, batches: [], error: "cyclic graph, cannot batch: #{cyc.join(' > ')}" } if cyc

    layer = {}
    all_nodes(edges).each { |n| assign_layer(n, edges, layer) }

    grouped = Hash.new { |h, k| h[k] = [] }
    layer.each { |n, l| grouped[l] << n }
    ordered = grouped.keys.sort.map { |l| grouped[l].sort }
    { ok: true, batches: ordered, error: nil }
  end

  def assign_layer(node, edges, layer)
    return layer[node] if layer.key?(node)

    needs = edges[node] || []
    layer[node] = needs.empty? ? 1 : 1 + needs.map { |t| assign_layer(t, edges, layer) }.max
  end

  # Every maximal-length chain (the longest path by node count) in `edges`,
  # up to `max_paths`, plus the true total count (computed by a polynomial
  # dynamic program, never by enumerating every path and truncating - a
  # fan-in graph has exponentially many). `critical_path` is the first under
  # a deterministic tie-break: the lexicographically smallest id sequence,
  # guaranteed by exploring successors in ascending id order depth-first.
  def critical_paths(edges, max_paths: DEFAULT_MAX_PATHS)
    cyc = GraphEdges.cycle(edges)
    if cyc
      return { ok: false, paths: [], critical_path: nil, hops: 0, total: 0, downstream_hops: {},
                error: "cyclic graph, cannot compute a critical path: #{cyc.join(' > ')}" }
    end

    nodes = all_nodes(edges)
    successors = Hash.new { |h, k| h[k] = [] }
    edges.each { |id, targets| (targets || []).each { |t| successors[t] << id } }

    longest = {}
    nodes.each { |n| compute_longest(n, successors, longest) }

    roots = nodes.select { |n| (edges[n] || []).empty? }
    return { ok: true, paths: [], critical_path: nil, hops: 0, total: 0, downstream_hops: longest, error: nil } if roots.empty?

    max_len = roots.map { |r| longest[r] }.max
    count_memo = {}
    total = roots.select { |r| longest[r] == max_len }.sum { |r| count_of_longest(r, successors, longest, count_memo) }

    paths = []
    roots.sort.each do |r|
      break if paths.length >= max_paths
      next unless longest[r] == max_len

      enumerate_longest(r, successors, longest, [r], paths, max_paths)
    end

    { ok: true, paths: paths, critical_path: paths.first, hops: max_len, total: total,
      downstream_hops: longest, error: nil }
  end

  # The longest remaining chain (in nodes) starting at each node, downstream
  # toward a leaf. Used by CriticalPathRanker to order off-path nodes.
  def downstream_hops(edges)
    critical_paths(edges)[:downstream_hops]
  end

  def compute_longest(node, successors, memo)
    return memo[node] if memo.key?(node)

    succs = successors[node] || []
    memo[node] = succs.empty? ? 1 : 1 + succs.map { |s| compute_longest(s, successors, memo) }.max
  end

  def count_of_longest(node, successors, longest, memo)
    return memo[node] if memo.key?(node)

    succs = (successors[node] || []).select { |s| longest[s] == longest[node] - 1 }
    memo[node] = succs.empty? ? 1 : succs.sum { |s| count_of_longest(s, successors, longest, memo) }
  end

  def enumerate_longest(node, successors, longest, path, results, max_paths)
    return if results.length >= max_paths

    succs = (successors[node] || []).select { |s| longest[s] == longest[node] - 1 }.sort
    if succs.empty?
      results << path.dup
      return
    end

    succs.each do |s|
      return if results.length >= max_paths

      enumerate_longest(s, successors, longest, path + [s], results, max_paths)
    end
  end

  # --- n4: the ranker seam ------------------------------------------------------

  def build_row(id:, kind:, batch:, retry_flag:, downstream_hops:, on_critical_path:)
    {
      id: id, kind: kind, batch: batch, retry: retry_flag,
      downstream_hops: downstream_hops, on_critical_path: on_critical_path,
    }.freeze
  end

  def ready_rows(views, batch_result, path_result)
    batches_list = batch_result[:ok] ? batch_result[:batches] : []
    batch_index = {}
    batches_list.each_with_index { |grp, i| grp.each { |id| batch_index[id] = i + 1 } }
    downstream = path_result[:ok] ? path_result[:downstream_hops] : {}
    crit_set = (path_result[:ok] ? path_result[:critical_path] : nil) || []

    views.each_with_object([]) do |(id, view), rows|
      next unless view[:ready]

      rows << build_row(
        id: id,
        kind: view[:kind],
        batch: batch_index[id] || 0,
        retry_flag: view[:state] == "failed_verification" || view[:attempts].to_i.positive?,
        downstream_hops: downstream[id] || 0,
        on_critical_path: crit_set.include?(id)
      )
    end
  end

  # FinishFirstRanker (D10, default): prefers a retry over a fresh node, then
  # the deeper batch (closer to finishing a chain already underway) over the
  # shallower one, tie-broken on id.
  class FinishFirstRanker
    def rank(rows)
      rows.sort_by { |r| [r[:retry] ? 0 : 1, -r[:batch].to_i, r[:id].to_s] }
    end

    def name
      "finish-first"
    end
  end

  # CriticalPathRanker (D10): prefers a node on a critical path, then orders
  # the rest by their own longest remaining chain, tie-broken on id.
  class CriticalPathRanker
    def rank(rows)
      rows.sort_by { |r| [r[:on_critical_path] ? 0 : 1, -r[:downstream_hops].to_i, r[:id].to_s] }
    end

    def name
      "critical-path"
    end
  end
end
