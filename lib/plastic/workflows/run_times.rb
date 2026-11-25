# frozen_string_literal: true

require "time"
require_relative "../clock"

module Plastic
  module Workflows
    # When a run started and ended and how long it took. The times show in the zone of the machine, as every time a person reads does;
    # the length comes from the stored times.
    module RunTimes
      # The `started ..., ended ..., length ...` part of a run line; a run with no end yet says running. `zone` is an offset such as +09:00;
      # with none, the times show in the zone of the machine.
      def self.line(run, zone = nil) = span(run.started_at, run.ended_at, zone)

      def self.span(started, ended, zone = nil)
        return nil unless started

        shown = "started #{Plastic.local(started, zone)}"
        ended ? "#{shown}, ended #{Plastic.local(ended, zone)}, length #{length(seconds(started, ended))}" : "#{shown}, running"
      end

      # The whole seconds from the start of a run to its end, from the stored times.
      def self.seconds(started, ended) = (Time.iso8601(ended) - Time.iso8601(started)).to_i

      # A length of whole seconds in plain words: under 1s, 42s, 4m 12s, 1h 2m 3s.
      def self.length(total)
        return "under 1s" if total < 1

        hours, rest = total.divmod(3600)
        minutes, secs = rest.divmod(60)
        return "#{hours}h #{minutes}m #{secs}s" if hours.positive?

        minutes.positive? ? "#{minutes}m #{secs}s" : "#{secs}s"
      end
    end
  end
end
