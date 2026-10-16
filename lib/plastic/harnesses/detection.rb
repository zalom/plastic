# frozen_string_literal: true

require_relative "../harnesses"

module Plastic
  module Harnesses
    # Names the harness that sent a hook event, by the first of: a field of
    # the event, a session variable equal to the event's session, the
    # transcript path, the nearest ancestor process, and AI_AGENT for a
    # harness the registry lacks. See docs/reference/harness-adapters.md.
    class Detection
      UNKNOWN = "unknown"
      AGENT = "AI_AGENT"

      def initialize(event:, env:, processes:, session_id: event[:session_id])
        @event = event
        @env = env
        @processes = processes
        @session_id = session_id
      end

      def self.first(&) = Harnesses.all.find(&)&.name

      def harness = by_event || by_variable || by_transcript || by_process || by_agent || UNKNOWN

      private

      def by_event
        named = @event[:harness].to_s
        Harnesses.registered?(named) ? named : Detection.first { |harness| harness.wrote?(@event) }
      end

      def by_variable
        session = @session_id
        session && Detection.first { |harness| harness.session(@env) == session }
      end

      def by_transcript
        path = @event[:transcript_path].to_s
        Detection.first { |harness| harness.transcribed?(path) } unless path.empty?
      end

      def by_process = Harnesses.nearest(@processes)&.name

      def by_agent
        agent = @env[AGENT].to_s.strip
        agent unless agent.empty? || Harnesses.registered?(agent)
      end
    end
  end
end
