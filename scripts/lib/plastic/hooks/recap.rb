# frozen_string_literal: true

module Plastic
  module Hooks
    # What a session start prints for one session: the state the rows alone
    # carry, so a cleared or compacted session reads it back.
    class Recap
      FIRST_LINES = {
        "clear" => "Plastic: the context was cleared. The rows below carry the state; run plastic next.",
        "compact" => "Plastic: the session was compacted. The rows below carry the state; run plastic next.",
        "resume" => "Plastic: a resumed session. The rows below carry the state; run plastic next."
      }.freeze
      MAX_OPEN = 10
      SAVEPOINT_LINES = 5

      def initialize(retrieval, session_id:, source:, directory:)
        @retrieval = retrieval
        @session_id = session_id
        @source = source.to_s
        @directory = directory
      end

      # The lines to print, first line first.
      def lines = [first_line, *open_intent_lines, *previous_session_lines, *in_progress_lines, *note_line]

      private

      def first_line
        FIRST_LINES.fetch(@source) { "Plastic: a new session in store #{@retrieval.store}. Run plastic next before anything else." }
      end

      def open_intent_lines
        open = @retrieval.intents.select(&:open?)
        rest = open.size - MAX_OPEN
        [*open.first(MAX_OPEN).map { |intent| "open: #{intent.heading}#{last_run(intent.intent_id)}" }, *("and #{rest} more" if rest.positive?)]
      end

      def last_run(intent_id)
        run = @retrieval.last_run(intent_id)
        run ? ", last run #{run.summary}" : ""
      end

      # A clear reads its directory's own ending first (review A1); every
      # other case reads the store's latest other session.
      def predecessor
        @predecessor ||= clear_predecessor || @retrieval.previous_session(@session_id)
      end

      def clear_predecessor
        @source == "clear" && @retrieval.predecessor(@session_id, directory: @directory, prefer_reason: "clear")
      end

      def previous_session_lines
        return [] if FIRST_LINES.key?(@source) || !predecessor

        ["previous #{predecessor.summary}", *touched_line]
      end

      def touched_line
        touched = @retrieval.touched(predecessor.session_id).join(", ")
        touched.empty? ? [] : ["touched: #{touched}"]
      end

      def in_progress_lines
        Array(in_progress_intent).flat_map { |intent| ["in progress: #{intent.label}", *savepoint_lines(intent.intent_id)] }
      end

      def savepoint_lines(intent_id)
        @retrieval.savepoints(intent_id).last(SAVEPOINT_LINES).map { |savepoint| "  #{savepoint.line}" }
      end

      # The first open intent this session touched, else the one its predecessor touched.
      def in_progress_intent
        sessions = [@session_id, predecessor&.session_id].compact
        sessions.lazy.flat_map { |session_id| @retrieval.touched(session_id) }
          .filter_map { |intent_id| @retrieval.intent(intent_id) }.find(&:open?)
      end

      def note_line
        text = @retrieval.session(@session_id)&.note || predecessor&.note
        text ? ["note: #{text}"] : []
      end
    end
  end
end
