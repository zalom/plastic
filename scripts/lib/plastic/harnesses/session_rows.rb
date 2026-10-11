# frozen_string_literal: true

require_relative "../graph/database"

module Plastic
  module Harnesses
    # The harness and start time of session rows in the home's local
    # database. A home with no local database has no rows, and reading it
    # makes none.
    class SessionRows
      SQL = "SELECT harness, started_at FROM sessions WHERE session_id = :session_id"

      def initialize(plastic_home)
        @local = Graph::Database::Local.new(plastic_home)
      end

      def harness(session_id) = row(session_id)&.fetch("harness")

      def latest(session_ids) = session_ids.filter_map { |session_id| started(session_id) }.max&.last

      private

      def started(session_id) = row(session_id)&.then { |found| [found["started_at"].to_s, session_id] }

      def row(session_id) = (@local.row(SQL, session_id:) if File.file?(@local.path))
    end
  end
end
