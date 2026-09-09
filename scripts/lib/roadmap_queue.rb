# encoding: UTF-8
# frozen_string_literal: true

require "time"
require "json"
require_relative "roadmap_savepoint"
require_relative "graph_file"
require_relative "graph_edges"

# FileOrderRanker - the default value-ordering strategy: today's roadmap file order,
# unchanged. This is the intent-173 ranking-swap seam (sibling to the 147 DB-swap seam): a
# future scored ranker (RICE/ICE/WSJF/pairwise) implements the same #rank/#name pair and is
# injected through RoadmapQueue's ranker: keyword, with no change to parsing, frontier
# detection, gating, INDEX reconciliation, or the JSON contract.
class FileOrderRanker
  def rank(entries)
    entries
  end

  def name
    "file-order"
  end
end

# RoadmapQueue - the one deterministic reader the auto loop and plastic-intent-continuing
# both call (intent 148). Constructor-DI, hermetic: clock and paths injected, no eval, no ENV
# or global config seam. It does two things: liveness-ranks a tier's roadmaps/*.md files
# (porting plastic-intent-continuing's read-time algorithm), and, within the winning
# roadmap, selects the frontier wave plus its dispatchable set (D-b), value-ordered by the
# injected ranker (default FileOrderRanker, the intent-173 swap seam). Every frontier token is
# reconciled against INDEX.md first, INDEX wins. Reads through the 134 ledger via the public
# RoadmapSavepoint.ledger_path_for; never writes anything, never modifies roadmap_savepoint.rb.
class RoadmapQueue
  STATUSES = %w[queued delivering delivered abandoned blocked].freeze

  # Entry line parser, anchored on the status vocabulary rather than end of line, so a trailing
  # parenthetical ("delivering (owner ruling...)") does not defeat the match. Accepts the em
  # dash or a hyphen as the separator; roadmap .md files are store-internal and use the em dash.
  # Intent 331c: group 3 captures the entry's own title text (between the id and the status
  # separator), so a screen reader has it without a second parser; group 4 (was 3) is the status.
  ENTRY = /\A-\s*\[([ xX])\]\s+(\S+)\s+(.*?)[—-]\s*(queued|delivering|delivered|abandoned|blocked)\b/.freeze

  WAVE_HEADING = /\A###\s+(.+?)\s*\z/.freeze

  LOG_LINE = /\A-\s+(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2})\s+UTC\b/.freeze

  def initialize(roadmaps_dir:, index_path: nil, now: Time.now, ranker: FileOrderRanker.new)
    @roadmaps_dir = roadmaps_dir
    @index_path   = index_path
    @now          = now
    @ranker       = ranker
  end

  # Auto-loop mode: break ties deterministically, report the winner's frontier state.
  def queue
    analyze(mode: "queue")
  end

  # Continuing mode: return tie_candidates instead of breaking a tie.
  def which
    analyze(mode: "which")
  end

  # Intent 331c (D6/R1): the one public reader for ONE roadmap's parsed, INDEX-reconciled shape,
  # so a screen never carries a second parser that can drift from this class's own grammar. Same
  # reconciliation (`reconcile`) and the same frontier selection (`frontier_for`, R17) `queue`/
  # `which` use for the whole tier, scoped to the single file at `path`.
  def roadmap(path)
    parsed = reconcile([parse_roadmap(path)]).first
    {
      slug: parsed[:slug],
      path: parsed[:path],
      grouping: RoadmapSavepoint.grouping_heading(File.read(path)),
      batches: parsed[:waves],
      frontier: frontier_for(parsed),
    }
  end

  private

  def analyze(mode:)
    parsed = reconcile(roadmap_paths.map { |path| parse_roadmap(path) })
    ranked = rank_candidates(parsed)

    return payload(mode: mode, state: "none", roadmap: nil, frontier_wave: nil,
                    dispatchable: [], in_flight: [], blocked: [], tie: false,
                    tie_candidates: []) if ranked.empty?

    tied = tied_group(ranked)

    if tied.length > 1 && mode == "which"
      tie_candidates = tied.map do |c|
        { "roadmap" => c[:slug], "last_event" => c[:last_event].utc.iso8601,
          "reason" => "equally live, tied on last event time" }
      end
      return payload(mode: mode, state: "tie", roadmap: nil, frontier_wave: nil,
                      dispatchable: [], in_flight: [], blocked: [], tie: false,
                      tie_candidates: tie_candidates)
    end

    winner = ranked.first
    is_tie = tied.length > 1

    cyc = winner[:graph_edges] && GraphEdges.cycle(winner[:graph_edges][:edges])
    if cyc
      return payload(mode: mode, state: "error", roadmap: winner[:slug],
                      frontier_wave: "cyclic roadmap graph, cannot compute a frontier: #{cyc.join(' > ')}",
                      dispatchable: [], in_flight: [], blocked: blocked_for(winner),
                      tie: is_tie, tie_candidates: [])
    end

    frontier = frontier_for(winner)

    state =
      if frontier.nil?
        "exhausted"
      elsif !frontier[:dispatchable].empty?
        "dispatchable"
      else
        "in_flight"
      end

    payload(mode: mode, state: state, roadmap: winner[:slug],
            frontier_wave: frontier && frontier[:heading],
            dispatchable: frontier ? frontier[:dispatchable] : [],
            in_flight: frontier ? frontier[:in_flight] : [],
            blocked: blocked_for(winner),
            tie: is_tie,
            tie_candidates: [])
  end

  # --- enumerate + parse --------------------------------------------------------

  def roadmap_paths
    return [] unless @roadmaps_dir && Dir.exist?(@roadmaps_dir)
    Dir.glob(File.join(@roadmaps_dir, "*.md"))
       .reject { |p| p.end_with?(".savepoint.md") }
       .sort
  end

  def parse_roadmap(path)
    text = File.read(path)
    {
      slug: File.basename(path, ".md"), path: path,
      waves: parse_waves(RoadmapSavepoint.grouping_section_body(text, path: path)),
      graph_edges: parse_roadmap_graph(text),
    }
  end

  # D15: an exact "## Graph" heading line only, never a prefix - a live
  # roadmap can carry "## Graph (2026-09-01, superseded by ...)", which
  # GraphFile.section_body already treats as a non-match because it locates
  # a section by an exact stripped-line comparison. A section that yields no
  # real edge lines (GraphEdges.parse finds zero nodes) is treated the same
  # as no section at all: the fallback to wave order, both silent (D15).
  # Fence-aware (D18): a fenced example edge line is never read as real.
  def parse_roadmap_graph(text)
    section = GraphFile.section_body(text, "## Graph")
    return nil if section.nil?

    parsed = GraphEdges.parse(GraphFile.strip_fenced_blocks(section))
    return nil if parsed[:nodes].empty?

    parsed
  end

  def parse_waves(waves_body)
    waves = []
    current = nil
    waves_body.each_line do |line|
      stripped = line.chomp.strip
      if (m = stripped.match(WAVE_HEADING))
        current = { heading: m[1], entries: [] }
        waves << current
      elsif current && (em = stripped.match(ENTRY))
        current[:entries] << { id: em[2], text: em[3].strip, raw_status: em[4].downcase }
      end
    end
    waves
  end

  def section_body(text, heading)
    m = text.match(/^##\s+#{Regexp.escape(heading)}\s*$(.*?)(?=^##\s|\z)/m)
    m ? m[1] : ""
  end

  # --- INDEX reconciliation (INDEX wins), applied before classification --------

  def reconcile(parsed_list)
    parsed_list.each do |c|
      c[:waves].each do |wave|
        wave[:entries].each { |entry| entry[:status] = reconcile_status(entry[:id], entry[:raw_status]) }
      end
    end
    parsed_list
  end

  def reconcile_status(id, raw_status)
    case index_status_map[id]
    when "delivered" then "delivered"
    when "abandoned" then "abandoned"
    when "queued" then "queued"
    when :active then raw_status == "delivered" ? "delivering" : raw_status
    else raw_status
    end
  end

  def index_status_map
    return @index_status_map if defined?(@index_status_map)
    @index_status_map = {}
    path = resolved_index_path
    return @index_status_map unless path && File.exist?(path)

    text = File.read(path)
    { "Completed" => "delivered", "Abandoned" => "abandoned", "Active" => :active, "Future" => "queued" }.each do |heading, tag|
      section_body(text, heading).each_line do |line|
        stripped = line.strip
        next unless stripped.start_with?("- [")
        m = stripped.match(/\A-\s*\[(\S+)\s/)
        next unless m
        @index_status_map[m[1]] = tag
      end
    end
    @index_status_map
  end

  def resolved_index_path
    return @index_path if @index_path
    return nil unless @roadmaps_dir
    File.join(File.dirname(@roadmaps_dir), "INDEX.md")
  end

  # --- liveness ranking (ports plastic-intent-continuing's read-time algorithm) -

  def rank_candidates(parsed_list)
    parsed_list.map do |c|
      entries = c[:waves].flat_map { |w| w[:entries] }
      live = entries.any? { |e| %w[delivering blocked].include?(e[:status]) }
      c.merge(live: live, last_event: last_event_time(c[:path]))
    end.sort_by { |c| [c[:live] ? 0 : 1, -c[:last_event].to_i, c[:slug]] }
  end

  def tied_group(ranked)
    return [] if ranked.empty?
    top_key = [ranked.first[:live], ranked.first[:last_event].to_i]
    ranked.select { |c| [c[:live], c[:last_event].to_i] == top_key }
  end

  def last_event_time(path)
    ledger_path = RoadmapSavepoint.ledger_path_for(path)
    if File.exist?(ledger_path)
      last_line = File.readlines(ledger_path).map(&:strip).reject(&:empty?).last
      if last_line
        token = last_line[/\A(\S+)/, 1]
        begin
          return Time.iso8601(token) if token
        rescue ArgumentError
          # fall through to the Log fallback below
        end
      end
    end
    log_fallback_time(path)
  end

  def log_fallback_time(path)
    body = section_body(File.read(path), "Log")
    last = body.each_line.map { |l| l.chomp.strip }.select { |l| l.match?(LOG_LINE) }.last
    return Time.at(0) unless last

    m = last.match(LOG_LINE)
    y, mo, d = m[1].split("-").map(&:to_i)
    h, mi = m[2].split(":").map(&:to_i)
    Time.utc(y, mo, d, h, mi, 0)
  end

  # --- frontier + dispatchable selection (D-b, D15) -------------------------------

  # D15: a candidate with a real ## Graph section dispatches by its edges
  # (a delivered entry counts as done); one without, or whose graph section
  # yields no edges (parse_roadmap_graph already returns nil for that case),
  # keeps the wave-order behavior unchanged.
  def frontier_for(candidate)
    candidate[:graph_edges] ? graph_frontier_for(candidate) : wave_frontier_for(candidate)
  end

  def wave_frontier_for(candidate)
    candidate[:waves].each do |wave|
      statuses = wave[:entries].map { |e| e[:status] }
      next unless statuses.any? { |s| %w[queued delivering].include?(s) }

      queued = wave[:entries].select { |e| e[:status] == "queued" }
      delivering = wave[:entries].select { |e| e[:status] == "delivering" }

      # intent-173 ranking-swap seam: value-orders the dispatchable candidates only.
      ordered = @ranker.rank(queued)

      dispatchable = ordered.each_with_index.map do |e, i|
        { "id" => e[:id], "scope" => scope_label, "roadmap" => candidate[:slug],
          "wave" => wave[:heading], "status" => "queued", "rank" => i + 1 }
      end
      in_flight = delivering.map do |e|
        { "id" => e[:id], "roadmap" => candidate[:slug], "wave" => wave[:heading], "status" => "delivering" }
      end

      return { heading: wave[:heading], dispatchable: dispatchable, in_flight: in_flight }
    end
    nil
  end

  # D15's edge-driven frontier: the topological layers of the graph's edges,
  # walked in order; the first layer holding a dispatchable (all needs
  # delivered) or in-flight entry is the frontier. An id the graph names but
  # no batch lists is reported in `blocked` (finding 2, R-2), never a crash
  # and never an invented dispatchable entry with no title. An id a batch
  # lists that the graph does not name is never dropped either: it keeps
  # the pre-change wave behavior (the G4 partial-migration path) by being
  # folded in as needing nothing (never called on a cyclic graph: #analyze
  # checks that first and reports "error" instead).
  def graph_frontier_for(candidate)
    edges = candidate[:graph_edges][:edges].dup
    id_to_entry = {}
    wave_of_id = {}
    candidate[:waves].each do |wave|
      wave[:entries].each do |e|
        id_to_entry[e[:id]] = e
        wave_of_id[e[:id]] = wave[:heading]
      end
    end

    (id_to_entry.keys - all_graph_nodes(edges)).each { |id| edges[id] = [] }

    topological_layers(edges).each do |layer|
      layer_ids = layer.select { |id| id_to_entry.key?(id) }
      next if layer_ids.empty?

      queued_ready = layer_ids.select do |id|
        entry = id_to_entry[id]
        entry[:status] == "queued" &&
          (edges[id] || []).all? { |t| id_to_entry[t] && id_to_entry[t][:status] == "delivered" }
      end
      delivering_ids = layer_ids.select { |id| id_to_entry[id][:status] == "delivering" }
      next if queued_ready.empty? && delivering_ids.empty?

      ordered = @ranker.rank(queued_ready.map { |id| id_to_entry[id] })
      dispatchable = ordered.each_with_index.map do |e, i|
        { "id" => e[:id], "scope" => scope_label, "roadmap" => candidate[:slug],
          "wave" => wave_of_id[e[:id]], "status" => "queued", "rank" => i + 1 }
      end
      in_flight = delivering_ids.map do |id|
        { "id" => id, "roadmap" => candidate[:slug], "wave" => wave_of_id[id], "status" => "delivering" }
      end

      heading = dispatchable.first ? dispatchable.first["wave"] : in_flight.first["wave"]
      return { heading: heading, dispatchable: dispatchable, in_flight: in_flight }
    end
    nil
  end

  # Topological layers of `edges` ({id => [needs...]}): layer one is every
  # id needing nothing, layer k is every id all of whose needs sit in layers
  # below k. Never called on a cyclic graph (the caller checks first), so no
  # cycle guard is needed here.
  def topological_layers(edges)
    nodes = edges.keys.dup
    edges.each_value { |targets| (targets || []).each { |t| nodes << t unless nodes.include?(t) } }

    layer = {}
    assign = nil
    assign = lambda do |node|
      next layer[node] if layer.key?(node)

      needs = edges[node] || []
      layer[node] = needs.empty? ? 1 : 1 + needs.map { |t| assign.call(t) }.max
    end
    nodes.each { |n| assign.call(n) }

    grouped = Hash.new { |h, k| h[k] = [] }
    layer.each { |n, l| grouped[l] << n }
    grouped.keys.sort.map { |l| grouped[l].sort }
  end

  def blocked_for(candidate)
    explicit = candidate[:waves].flat_map do |wave|
      wave[:entries].select { |e| e[:status] == "blocked" }.map do |e|
        { "id" => e[:id], "roadmap" => candidate[:slug], "wave" => wave[:heading], "status" => "blocked" }
      end
    end
    explicit + graph_reporting_blocked(candidate)
  end

  # R-2 (finding 2): a graph naming an id no batch lists is reported, not
  # swallowed - both the unnamed id itself, and any batch entry whose own
  # declared need points straight at it, which would otherwise sit queued
  # forever with nothing in the payload explaining why. Keeps the invariant
  # that `state` is never "exhausted" while a queued entry sits unaccounted
  # for: an entry that can never resolve still shows up here.
  def graph_reporting_blocked(candidate)
    return [] unless candidate[:graph_edges]

    edges = candidate[:graph_edges][:edges]
    id_to_entry = candidate[:waves].flat_map { |w| w[:entries] }.each_with_object({}) { |e, h| h[e[:id]] = e }
    unreported = all_graph_nodes(edges).reject { |id| id_to_entry.key?(id) }

    reported = unreported.map do |id|
      { "id" => id, "roadmap" => candidate[:slug], "wave" => nil, "status" => "unreported",
        "reason" => "graph names #{id.inspect}, no batch entry" }
    end

    stuck = []
    id_to_entry.each do |id, entry|
      next unless entry[:status] == "queued"

      (edges[id] || []).each do |target|
        next unless unreported.include?(target)

        stuck << { "id" => id, "roadmap" => candidate[:slug], "wave" => wave_heading_for(candidate, id),
                   "status" => "unreported",
                   "reason" => "#{id} needs #{target}, which the graph declares but no batch lists" }
      end
    end

    reported + stuck
  end

  def wave_heading_for(candidate, id)
    candidate[:waves].each { |w| return w[:heading] if w[:entries].any? { |e| e[:id] == id } }
    nil
  end

  def all_graph_nodes(edges)
    nodes = edges.keys.dup
    edges.each_value { |targets| (targets || []).each { |t| nodes << t unless nodes.include?(t) } }
    nodes
  end

  # --- scope + payload -----------------------------------------------------------

  def scope_label
    m = @roadmaps_dir.to_s.match(%r{/projects/([^/]+)/roadmaps/?\z})
    m ? "project:#{m[1]}" : "global"
  end

  def payload(mode:, state:, roadmap:, frontier_wave:, dispatchable:, in_flight:, blocked:, tie:, tie_candidates:)
    {
      "generated_for" => "roadmap-next",
      "mode" => mode,
      "scope" => scope_label,
      "state" => state,
      "roadmap" => roadmap,
      "frontier_wave" => frontier_wave,
      "dispatchable_queue" => dispatchable,
      "in_flight" => in_flight,
      "blocked" => blocked,
      "tie" => tie,
      "tie_candidates" => tie_candidates,
      "ranking_strategy" => @ranker.name,
      "generated_at" => @now.utc.iso8601,
    }
  end
end
