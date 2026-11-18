# frozen_string_literal: true

require_relative "../graph/knowledge/intent"
require_relative "../graph/knowledge/intent/listing"
require_relative "../graph/work/delivery_action"
require_relative "../graph/work/last_log_lines"
require_relative "../graph/work/session_intent"
require_relative "compact_recap"
require_relative "predecessor_session"

module Plastic
  module Hooks
    # What a session start prints for one session: the state the rows alone
    # carry, so a cleared or compacted session reads it back.
    class Recap
      FIRST_LINES = {
        "clear" => "Plastic: the context was cleared. The rows below carry the state; run plastic graph resume.",
        "compact" => CompactRecap::FIRST_LINE,
        "resume" => "Plastic: a resumed session. The rows below carry the state; run plastic graph resume.",
        "fork" => "Plastic: a resumed session. The rows below carry the state; run plastic graph resume."
      }.freeze
      LOG_LINES = 5
      LAPSED = "intent %<intent_id>s: the claim of this session on node %<id>s lapsed (last renewed %<seen_at>s); plastic node claim %<intent_id>s %<id>s takes it again"

      def initialize(retrieval, session_id:, source:, directory:)
        @retrieval = retrieval
        @session_id = session_id
        @source = source.to_s
        @predecessor = PredecessorSession.new(retrieval, session_id: session_id, source: @source, directory: directory)
      end

      # The lines to print, first line first.
      def lines(now:) = (@source == "compact") ? compact_lines : full_lines(now)

      private

      def full_lines(now) = [first_line, *open_intent_lines, *lapsed_claim_lines(now), *previous_session_lines, *in_progress_lines, *note_line]

      def compact_lines = CompactRecap.new(@retrieval, session_id: @session_id).lines

      def first_line
        FIRST_LINES.fetch(@source) { "Plastic: a new session in store #{@retrieval.store}. Run plastic next before anything else." }
      end

      def open_intent_lines
        Graph::Knowledge::Intent::Listing.lines(@retrieval.intents) { |intent| "#{intent.heading}#{last_run(intent.intent_id)}" }
          .map { |name, text| "#{name}: #{text}" }
      end

      def lapsed_claim_lines(now)
        own = @retrieval.claimed_nodes.select { |node| node.claimed_by == @session_id && unfinished?(node.intent_id) }
        own.select { |node| node.lapsed?(now) }.map { |node| format(LAPSED, **node.to_h) }
      end

      # The intent exists and its work is not over.
      def unfinished?(intent_id) = @retrieval.intent(intent_id)&.closed? == false

      def last_run(intent_id)
        run = @retrieval.last_run(intent_id)
        run ? ", last run #{run.summary}#{live_next(intent_id)}" : ""
      end

      def live_next(intent_id)
        command, = Graph::Work::DeliveryAction.new(@retrieval, intent_id).call
        command ? ", next: #{command}" : ""
      end

      def previous_session_lines = FIRST_LINES.key?(@source) ? [] : @predecessor.lines

      def in_progress_lines
        Array(in_progress_intent).flat_map { |intent| ["in progress: #{intent.label}", *log_lines(intent.intent_id)] }
      end

      def log_lines(intent_id)
        Graph::Work::LastLogLines.new(@retrieval, LOG_LINES).lines(intent_id).map { |line| "  #{line}" }
      end

      # The intent this session works on, else the one its predecessor worked on.
      def in_progress_intent
        sessions = [@session_id, @predecessor.session&.session_id].compact
        sessions.lazy.filter_map { |session_id| Graph::Work::SessionIntent.new(@retrieval, session_id).intent }.first
      end

      def note_line
        text = @retrieval.session(@session_id)&.note || @predecessor.session&.note
        text ? ["note: #{text}"] : []
      end
    end
  end
end
