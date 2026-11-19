# frozen_string_literal: true

require_relative "wiring"
require_relative "../graph/backup/daily"

module Plastic
  class CLI
    # The daily backups a call takes before its work, when backup.daily is on:
    # the start-of-day backup of every store, or at a session end the
    # end-of-day one. Each store that fails prints one line on standard
    # error, and the call goes on.
    class DayBackup
      def initialize(environment)
        @environment = environment
        @home = environment.plastic_home
      end

      # The moment is begin_day for a call, or end_session for the session end.
      def take(moment)
        return unless Wiring.daily_backups?(@home)

        Graph::Backup::Daily.new(home: @home, now: @environment.now).public_send(moment).each { |failure| say(**failure.to_h) }
      end

      private

      def say(slug:, reason:) = @environment.err.puts("backup: #{slug} was not backed up (#{reason}); the call goes on")
    end
  end
end
