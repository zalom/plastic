# frozen_string_literal: true

require_relative "../hook"

module Plastic
  module Hooks
    # SessionStart: opens the session row, then prints the state the rows
    # alone carry, so a cleared or compacted session reads it back. Nothing
    # here is call memory: a hook keeps no routine run.
    class Resume < Hook
      option :harness, switch: "--harness NAME", text: "the harness calling this hook", default: "claude-code"

      FIRST_LINES = {
        "clear" => "Plastic: the context was cleared. The rows below carry the state; run plastic next.",
        "compact" => "Plastic: the session was compacted. The rows below carry the state; run plastic next.",
        "resume" => "Plastic: a resumed session. The rows below carry the state; run plastic next."
      }.freeze
      MAX_OPEN = 10
      OPEN_STATUSES = %w[open active].freeze

      def respond(event)
        sid = session_id(event)
        sid.nil? ? stderr_line : open_session_row(sid)
        lines(event, sid).join("\n")
      end

      private

      def open_session_row(sid)
        store.work.open_session(sid, harness: parsed[:harness], directory: directory)
      end

      def lines(event, sid)
        store.work.ignore_databases
        [first_line(event), *open_intent_lines, *previous_session_lines(event, sid), *in_progress_lines(event, sid),
          *note_line(event, sid)].compact
      end

      def store = (@store ||= Graph.open(home: scope.plastic_home, store: scope.slug, session: @sid))

      def stderr_line
        environment.err.puts "plastic hook: the event names no session; nothing recorded"
        nil
      end

      def source(event) = event[:source].to_s

      def first_line(event)
        FIRST_LINES.fetch(source(event)) do
          "Plastic: a new session in store #{scope.slug}. Run plastic next before anything else."
        end
      end

      def open_intents = store.retrieval.intents.select { |intent| OPEN_STATUSES.include?(intent.status) }

      def open_intent_lines
        shown = open_intents.first(MAX_OPEN)
        rest = open_intents.size - shown.size
        lines = shown.map { |intent| open_intent_line(intent) }
        lines << "and #{rest} more" if rest.positive?
        lines
      end

      def open_intent_line(intent)
        run = store.retrieval.last_run(intent.intent_id)
        header = "open: #{intent.intent_id} #{intent.title} (#{intent.status})"
        return header unless run

        next_part = run.next_command ? ", next: #{run.next_command}" : ""
        "#{header}, last run #{run.tool} #{run.status} #{run.updated_at}#{next_part}"
      end

      # The predecessor a case reads: a clear reads its directory's own
      # ending first (review A1); every other case reads the store's latest.
      def predecessor(event, sid)
        return nil unless source(event) == "clear"

        store.retrieval.predecessor(sid, directory: directory, prefer_reason: "clear")
      end

      def predecessor_or_latest(event, sid) = predecessor(event, sid) || store.retrieval.previous_session(sid)

      def previous_session_lines(event, sid)
        return [] if FIRST_LINES.key?(source(event))

        previous = predecessor_or_latest(event, sid)
        return [] unless previous

        [previous_session_line(previous), *touched_line(previous.session_id)]
      end

      def previous_session_line(previous)
        if previous.ended?
          "previous session #{previous.session_id} ended #{previous.ended_at} (#{previous.end_reason})"
        else
          "previous session #{previous.session_id} last turn #{previous.last_turn_at}"
        end
      end

      def touched_line(session_id)
        ids = store.retrieval.touched(session_id)
        ids.empty? ? [] : ["touched: #{ids.join(", ")}"]
      end

      def in_progress_lines(event, sid)
        intent_id = in_progress_intent_id(event, sid)
        return [] unless intent_id

        intent = store.retrieval.intent(intent_id)
        return [] unless intent

        lines = store.retrieval.savepoints(intent_id).last(5).map { |line| "  #{line.line}" }
        ["in progress: #{intent.intent_id} #{intent.title}", *lines]
      end

      def in_progress_intent_id(event, sid)
        first_open(store.retrieval.touched(sid)) || first_open(store.retrieval.touched(predecessor_or_latest(event, sid)&.session_id))
      end

      def first_open(ids)
        Array(ids).find { |id| store.retrieval.intent(id) && OPEN_STATUSES.include?(store.retrieval.intent(id).status) }
      end

      def note_line(event, sid)
        text = store.retrieval.session(sid)&.note || predecessor_or_latest(event, sid)&.note
        text ? ["note: #{text}"] : []
      end

      def session_id(event)
        @sid = super
      end
    end
  end
end
