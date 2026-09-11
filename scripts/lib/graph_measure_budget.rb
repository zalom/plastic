# encoding: UTF-8
# frozen_string_literal: true

require "digest"
require "json"
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

  def declared_budget_for(dir, node, node_reader)
    path = NodePacket.find_node_path(dir, node)
    return :unavailable unless path

    parsed = node_reader.call(path)
    budget = parsed && parsed[:budget]
    budget.is_a?(Integer) ? budget : :unavailable
  end
  private_class_method :declared_budget_for

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
  def detect_ceiling(nodes)
    usable = []
    nodes.each do |id, node|
      budget = node[:declared_budget]
      next unless budget.is_a?(Integer)

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
    well_below = usable.all? { |u| candidate < u[:budget] }

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
