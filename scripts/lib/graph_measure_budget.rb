# encoding: UTF-8
# frozen_string_literal: true

require "digest"
require "json"
require "tmpdir"
require_relative "node_ledger"
require_relative "node_file"
require_relative "node_packet"
require_relative "packet_wrapper"

# GraphMeasureBudget (intent 343, G10, n4): whether the `budget:` a node's
# envelope declares (327 C19, D47) is a ceiling that ever actually held.
# Intent 340 found at 22:14Z on 2026-09-10 that every runner-built packet
# was capped at 8000 tokens whatever the node declared (v1 major M7); this
# module is the measurement of whether that still holds, from the ledger
# and the real packet files alone.
#
# Read-only (spec D2): it opens `nodes/*.md`, `savepoint.md` and files under
# `packets/`, and writes nothing. A measure with no source prints
# `:unavailable`, never zero and never blank (spec D3); a packet file named
# by `packet=` that is not on disk is counted and named by its sha, never
# silently treated as zero bytes (spec D4).
#
# Adds no second parser and no second estimator: `NodeLedger` owns the
# transition-line format, `NodeFile` owns the envelope's `budget:`,
# `NodePacket` owns packet path resolution and attempt numbering, and
# `PacketWrapper.estimate_tokens` is the one token formula, the same the
# packet builder enforced with (spec D8).
module GraphMeasureBudget
  module_function

  SAVEPOINT_FILE = "savepoint.md"
  UNAVAILABLE = "unavailable"

  # {ok:, nodes: {id => {declared_budget:, attempts: [...]}}, ceiling: {...}}.
  # Never raises: a missing savepoint.md, a node with no envelope file, and a
  # packet= naming a file that does not exist on disk all resolve to
  # `:unavailable` fields rather than an exception.
  def read(intent_dir, node_reader: NodeFile.method(:parse))
    dir = File.expand_path(intent_dir.to_s)
    content = read_content(File.join(dir, SAVEPOINT_FILE))
    entries = NodeLedger.entries_from_content(content)

    running_indices = Hash.new { |h, k| h[k] = [] }
    entries.each_with_index do |e, idx|
      next if e[:torn] || e[:state] != "running"

      running_indices[e[:subject]] << idx
    end

    nodes = {}
    running_indices.each do |subject, indices|
      declared_budget = declared_budget_for(dir, subject, node_reader)
      attempts = indices.map do |idx|
        entry = entries[idx]
        # Row 4.5: the attempt number is NodePacket's own count of non-torn
        # `running` lines up to and including this one, never
        # ReadySet.attempts_count (which resets after `done`, `superseded`
        # or `abandoned` and answers "attempts left", not "which attempt was
        # this line").
        attempt_number = NodePacket.compute_attempt_number(
          intent_dir: dir, node: subject, lease_flag_given: false, entries: entries[0..idx]
        )
        build_attempt(dir, subject, attempt_number, entry, declared_budget)
      end
      nodes[subject] = { declared_budget: declared_budget, attempts: attempts }
    end

    record = { ok: true, nodes: nodes, ceiling: detect_ceiling(nodes) }
    deep_freeze(record)
  end

  # --- rendering -----------------------------------------------------------

  def render_json(record)
    JSON.generate(model(record))
  end

  def render_text(record)
    m = model(record)
    lines = []
    lines.concat(node_block(m["nodes"]))
    lines << ""
    lines.concat(ceiling_block(m["ceiling"]))
    "#{lines.join("\n")}\n"
  end

  def model(record)
    {
      "nodes" => sort_ids(record[:nodes].keys).map { |id| node_model(id, record[:nodes][id]) },
      "ceiling" => ceiling_model(record[:ceiling]),
    }
  end

  def node_model(id, node)
    {
      "id" => id,
      "declared_budget" => av(node[:declared_budget]),
      "attempts" => node[:attempts].map { |a| attempt_model(a) },
    }
  end
  private_class_method :node_model

  def attempt_model(a)
    {
      "attempt" => a[:attempt],
      "packet_sha_declared" => av(a[:packet_sha_declared]),
      "file_exists" => a[:file_exists],
      "packet_sha_actual" => av(a[:packet_sha_actual]),
      "sha_match" => a[:sha_match],
      "bytes" => av(a[:bytes]),
      "estimate_tokens" => av(a[:estimate_tokens]),
      "hop" => a[:hop],
      "effective_tokens" => av(a[:effective_tokens]),
      "over_budget" => av(a[:over_budget]),
    }
  end
  private_class_method :attempt_model

  def ceiling_model(c)
    {
      "detected" => c[:detected],
      "value" => c[:value] ? c[:value] : UNAVAILABLE,
      "node_count" => c[:node_count],
      "attempt_count" => c[:attempt_count],
      "reason" => c[:reason].to_s,
    }
  end
  private_class_method :ceiling_model

  def node_block(nodes)
    lines = ["== Budget =="]
    if nodes.empty?
      lines << "(no packet attempts recorded)"
      return lines
    end

    lines << "| Node | Attempt | Declared budget | Bytes | Est tokens | Hop | Effective tokens | Over budget | Sha match |"
    lines << "| --- | --- | --- | --- | --- | --- | --- | --- | --- |"
    nodes.each do |n|
      n["attempts"].each do |a|
        lines << "| #{n['id']} | #{a['attempt']} | #{n['declared_budget']} | #{a['bytes']} | " \
                 "#{a['estimate_tokens']} | #{a['hop']} | #{a['effective_tokens']} | #{a['over_budget']} | #{a['sha_match']} |"
      end
    end
    lines
  end
  private_class_method :node_block

  def ceiling_block(c)
    [
      "== Suspected ceiling ==",
      "detected: #{c['detected']}",
      "value: #{c['value']}#{c['value'] == UNAVAILABLE ? '' : ' tokens'}",
      "based on: #{c['node_count']} nodes, #{c['attempt_count']} attempts (reason: #{c['reason']})",
    ]
  end
  private_class_method :ceiling_block

  # --- reading ---------------------------------------------------------------

  def read_content(path)
    return "" unless path && File.exist?(path)

    File.read(path).scrub
  end
  private_class_method :read_content

  # B6 (v1 review): `node_reader` (NodeFile.parse by default) reads its own
  # path and does not scrub, so one bad byte anywhere in a node envelope
  # raised out of NodeFile's regex matching and took the whole `budget` verb
  # down (reproduced by appending an invalid UTF-8 byte to a copy of 340's
  # nodes/n1.md: `budget` exited 1 with "internal error: invalid byte
  # sequence in UTF-8", the same as `cohorts`, while `intent` - which never
  # calls NodeFile.parse without GraphMeasure's own `with_safe_path` guard -
  # stayed at exit 0). `GraphMeasure.with_safe_path` already solves exactly
  # this, but it is `private_class_method` (carried from n1, same pattern
  # n5's `GraphMeasureModels` already uses for its own `present?` and
  # `resolve_kind`): a local copy, not a second parser or a reopen.
  def declared_budget_for(dir, node, node_reader)
    path = NodePacket.find_node_path(dir, node)
    return :unavailable unless path

    parsed = with_safe_path(path) { |p| p ? node_reader.call(p) : nil }
    budget = parsed && parsed[:budget]
    budget.is_a?(Integer) ? budget : :unavailable
  end
  private_class_method :declared_budget_for

  # Own copy of GraphMeasure's `with_safe_path` (private there): scrub a
  # bad-UTF-8 file into a throwaway Dir.mktmpdir copy before handing it to a
  # reader that does not scrub itself, never writing into `intent_dir`
  # (spec D2).
  def with_safe_path(path)
    return yield(nil) unless path && File.exist?(path)

    raw = File.read(path)
    scrubbed = raw.scrub
    return yield(path) if scrubbed == raw

    Dir.mktmpdir("graph-measure-budget-scrub") do |tmp|
      safe_path = File.join(tmp, File.basename(path))
      File.write(safe_path, scrubbed)
      yield(safe_path)
    end
  end
  private_class_method :with_safe_path

  def build_attempt(dir, subject, attempt_number, entry, declared_budget)
    fields = entry[:fields] || {}
    packet_sha_declared = present?(fields["packet"]) ? fields["packet"] : :unavailable
    # D8: hop= is written once, on the running line; absent means no hop
    # block was appended (the feature predates this line, or hop is off),
    # never an unknown quantity to subtract.
    hop = present?(fields["hop"]) ? fields["hop"].to_i : 0
    path = NodePacket.packet_path(intent_dir: dir, node: subject, attempt: attempt_number)
    file_exists = File.exist?(path)

    if file_exists
      raw = File.binread(path)
      bytes = raw.bytesize
      sha_actual = Digest::SHA256.hexdigest(raw)[0, 12]
      estimate = PacketWrapper.estimate_tokens(raw)
      effective = estimate - hop
      over_budget = declared_budget.is_a?(Integer) ? effective > declared_budget : :unavailable
      sha_match = sha_actual == packet_sha_declared
    else
      bytes = :unavailable
      sha_actual = :unavailable
      estimate = :unavailable
      effective = :unavailable
      over_budget = :unavailable
      sha_match = false
    end

    {
      attempt: attempt_number,
      packet_sha_declared: packet_sha_declared,
      packet_path: path,
      file_exists: file_exists,
      packet_sha_actual: sha_actual,
      sha_match: sha_match,
      bytes: bytes,
      estimate_tokens: estimate,
      hop: hop,
      effective_tokens: effective,
      over_budget: over_budget,
      raw: entry[:raw],
    }
  end
  private_class_method :build_attempt

  def present?(value)
    !(value.nil? || value.to_s.strip.empty?)
  end
  private_class_method :present?

  # --- the suspected ceiling: spec matrix rows 4.8, 4.9 -----------------------

  # A run of packets whose estimates all fall under one value well below
  # their own declared budgets (row 4.8): the candidate ceiling is the
  # largest effective estimate among the usable attempts (every attempt
  # whose declared budget and packet file are both known), and it is only
  # reported when that value sits strictly under EVERY one of those
  # attempts' own declared budgets - never a "cluster within a few percent"
  # of each other, which never fires against a real spread of packet sizes.
  # Row 4.9: fewer than two distinct nodes never reports a ceiling; one
  # node's own repeated attempts are not evidence of a ceiling shared across
  # the intent.
  #
  # B5 (v1 review): `candidate < u[:budget]` alone reads "nothing went over
  # budget", which is true of every intent that simply stayed under its own
  # declared budgets - reproduced with two nodes estimated at 1999 and 1998
  # effective tokens against declared budgets of 2000 each, which the old
  # code reported as "detected: true, value: 1999" though there was no
  # ceiling there at all: both attempts used over 99.9% of their own
  # declared allowance, they just never quite crossed it.
  #
  # "Well below" needs a stated threshold: WELL_BELOW_RATIO is that
  # threshold, and a ceiling is reported only when the candidate uses no
  # more than this fraction of EVERY usable attempt's own declared budget.
  # Reproduced against 340's real packets: declared budgets there run from
  # 50000 to 160000 tokens (327 D47's per-kind defaults), and every
  # attempt's effective token count clusters between 3380 and 7717 - the
  # candidate (7717) is at most 7717/50000 = 15.4% of even the SMALLEST
  # declared budget among the usable attempts, so it clears this threshold
  # by a wide margin and 340 still reports a detected ceiling. The
  # synthetic 1999-vs-2000 case clears none of it (99.95%, not <= 50%) and
  # correctly reports no ceiling.
  WELL_BELOW_RATIO = 0.5

  # NEW-2 (v2 review, D21): `candidate <= budget * WELL_BELOW_RATIO` checked
  # against EVERY usable attempt in the intent, with no requirement that
  # more than one of them actually sit anywhere near the candidate. That
  # fires on any spread of generous, unrelated budgets (reproduced: nodes at
  # 3000, 7000 and 1200 effective tokens against declared budgets of
  # 100000, 100000 and 150000 reported "detected: true, value: 7000" though
  # only the 7000 attempt sits anywhere near that number), and it misses a
  # genuine shared ceiling under tight budgets, where the honest utilization
  # of a real cluster crosses 50% (reproduced: three nodes converging
  # tightly on 7717/7690/7650 against a declared 10000 each reported
  # "not_well_below_declared_budgets"). D21's own fix: a candidate is
  # evidence of a ceiling only once several distinct usable attempts
  # actually approach it from below (CLUSTER_BAND_RATIO), and the "well
  # below budget" bar only needs to be strict (WELL_BELOW_RATIO) when that
  # cluster is thin (fewer than SEVERAL_CLUSTER_THRESHOLD distinct nodes);
  # once several distinct nodes converge on the same value, the convergence
  # itself is the primary evidence and the budget bar relaxes to
  # CLUSTERED_WELL_BELOW_RATIO. 340's real cluster (five distinct nodes
  # converging between 6237 and 7717) clears either bar by a wide margin;
  # the two-node 1999/1998-vs-2000 case never reaches the cluster threshold
  # of three, so it still runs against the strict 50% bar unchanged.
  CLUSTER_BAND_RATIO = 0.8
  SEVERAL_CLUSTER_THRESHOLD = 3
  CLUSTERED_WELL_BELOW_RATIO = 0.9

  def detect_ceiling(nodes)
    usable = []
    nodes.each do |id, node|
      budget = node[:declared_budget]
      # D21: an attempt whose declared budget is absent or zero carries no
      # evidence either way and is disqualified from the comparison, never
      # the whole intent (reproduced: two nodes declaring a budget of 0
      # with 0 effective tokens each reported "detected: true, value: 0",
      # an artifact of comparing a candidate against a budget of 0 rather
      # than real evidence of a ceiling).
      next unless budget.is_a?(Integer) && budget.positive?

      node[:attempts].each do |a|
        next unless a[:effective_tokens].is_a?(Integer)

        usable << { node: id, effective: a[:effective_tokens], budget: budget }
      end
    end

    distinct_nodes = usable.map { |u| u[:node] }.uniq
    attempt_count = usable.length

    if distinct_nodes.length < 2
      return { detected: false, reason: :insufficient_nodes, value: nil,
                node_count: distinct_nodes.length, attempt_count: attempt_count }
    end

    candidate = usable.map { |u| u[:effective] }.max
    cluster = usable.select { |u| u[:effective] >= candidate * CLUSTER_BAND_RATIO }
    cluster_nodes = cluster.map { |u| u[:node] }.uniq

    if cluster_nodes.length < 2
      return { detected: false, reason: :no_cluster, value: nil,
                node_count: distinct_nodes.length, attempt_count: attempt_count }
    end

    ratio = cluster_nodes.length >= SEVERAL_CLUSTER_THRESHOLD ? CLUSTERED_WELL_BELOW_RATIO : WELL_BELOW_RATIO
    well_below = cluster.all? { |u| candidate <= u[:budget] * ratio }

    unless well_below
      return { detected: false, reason: :not_well_below_declared_budgets, value: nil,
                node_count: distinct_nodes.length, attempt_count: attempt_count }
    end

    { detected: true, reason: :ok, value: candidate, node_count: distinct_nodes.length, attempt_count: attempt_count }
  end
  private_class_method :detect_ceiling

  # --- formatting helpers ------------------------------------------------------

  def av(value)
    return UNAVAILABLE if value.nil? || value == :unavailable

    value
  end
  private_class_method :av

  def sort_ids(ids)
    ids.sort_by do |id|
      m = id.to_s.match(/\A([A-Za-z]+)(\d+)\z/)
      m ? [m[1], m[2].to_i] : [id.to_s, 0]
    end
  end
  private_class_method :sort_ids

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
