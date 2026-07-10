# encoding: UTF-8
# frozen_string_literal: true

require "time"
require "json"
require_relative "roadmap_savepoint"

# RoadmapQueue - the one deterministic reader the auto loop and plastic-roadmap-continuing
# both call (intent 148). Constructor-DI, hermetic: clock and paths injected, no eval, no ENV
# or global config seam. It does two things: liveness-ranks a tier's roadmaps/*.md files
# (porting plastic-roadmap-continuing's read-time algorithm), and, within the winning
# roadmap, selects the frontier wave plus its dispatchable set (D-b). Every frontier token is
# reconciled against INDEX.md first, INDEX wins. Reads through the 134 ledger via the public
# RoadmapSavepoint.ledger_path_for; never writes anything, never modifies roadmap_savepoint.rb.
class RoadmapQueue
  STATUSES = %w[queued delivering delivered abandoned blocked].freeze

  # Entry line parser, anchored on the status vocabulary rather than end of line, so a trailing
  # parenthetical ("delivering (owner ruling...)") does not defeat the match. Accepts the em
  # dash or a hyphen as the separator; roadmap .md files are store-internal and use the em dash.
  ENTRY = /\A-\s*\[([ xX])\]\s+(\S+)\s+.*?[—-]\s*(queued|delivering|delivered|abandoned|blocked)\b/.freeze

  WAVE_HEADING = /\A###\s+(.+?)\s*\z/.freeze

  LOG_LINE = /\A-\s+(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2})\s+UTC\b/.freeze

  def initialize(roadmaps_dir:, index_path: nil, now: Time.now)
    @roadmaps_dir = roadmaps_dir
    @index_path   = index_path
    @now          = now
  end

  # Auto-loop mode: break ties deterministically, report the winner's frontier state.
  def queue
    analyze(mode: "queue")
  end

  # Continuing mode: return tie_candidates instead of breaking a tie.
  def which
    analyze(mode: "which")
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
    { slug: File.basename(path, ".md"), path: path, waves: parse_waves(section_body(text, "Waves")) }
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
        current[:entries] << { id: em[2], raw_status: em[3].downcase }
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

  # --- liveness ranking (ports plastic-roadmap-continuing's read-time algorithm) -

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

  # --- frontier + dispatchable selection (D-b) ----------------------------------

  def frontier_for(candidate)
    candidate[:waves].each do |wave|
      statuses = wave[:entries].map { |e| e[:status] }
      next unless statuses.any? { |s| %w[queued delivering].include?(s) }

      queued = wave[:entries].select { |e| e[:status] == "queued" }
      delivering = wave[:entries].select { |e| e[:status] == "delivering" }

      dispatchable = queued.each_with_index.map do |e, i|
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

  def blocked_for(candidate)
    candidate[:waves].flat_map do |wave|
      wave[:entries].select { |e| e[:status] == "blocked" }.map do |e|
        { "id" => e[:id], "roadmap" => candidate[:slug], "wave" => wave[:heading], "status" => "blocked" }
      end
    end
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
      "generated_at" => @now.utc.iso8601,
    }
  end
end
