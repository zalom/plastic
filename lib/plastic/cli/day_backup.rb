# frozen_string_literal: true

require_relative "wiring"
require_relative "../graph/backup/daily"

module Plastic
  class CLI
    # The daily backups a call takes, when backup.daily is on: the
    # start-of-day backup of every store, or at a session end the end-of-day
    # one. It never raises. Each store that fails prints one line on standard
    # error, a failure outside one store prints one line too, and the call
    # goes on.
    class DayBackup
      def initialize(environment)
        @environment = environment
        @home = environment.plastic_home
      end

      # The moment is begin_day for a call, or end_session for the session end.
      def back_up(moment)
        return unless Wiring.daily_backups?(@home)

        Graph::Backup::Daily.new(home: @home, now: @environment.now).public_send(moment).each { |failure| say(**failure.to_h) }
      rescue => error
        err.puts("backup: the daily backups were not taken (#{error.message.lines.first.to_s.strip}); the call goes on")
      end

      private

      def err = @environment.err

      def say(slug:, reason:) = err.puts("backup: #{slug} was not backed up (#{reason}); the call goes on")
    end
  end
end
