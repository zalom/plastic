# frozen_string_literal: true

require_relative "../doctor"

module Plastic
  module Hooks
    # The one line a fresh session start prints about plastic doctor: how many
    # doctor checks fail for a registered harness, or, for a name the registry
    # lacks, what that name on the session row means. A doctor that breaks
    # says so on the error stream and adds no line.
    class DoctorLine
      FRESH_SOURCES = ["", "startup"].freeze

      FAILING_LINE = lambda do |count|
        "Plastic: doctor found #{count} failing #{(count == 1) ? "check" : "checks"}; run plastic doctor."
      end

      def initialize(scope, harness, session_id:, health:, err:)
        @harness = harness
        @session_id = session_id
        @failing = -> { health.call(scope, harness) }
        @err = err
      end

      def line(source)
        return unless FRESH_SOURCES.include?(source.to_s)

        Harnesses.registered?(@harness) ? failing_line : unregistered_line
      end

      private

      def failing_line = failing_count.then { |count| FAILING_LINE.call(count) if count.positive? }

      def failing_count
        @failing.call.size
      rescue => error
        @err.puts "plastic hook: #{error.message}"
        0
      end

      def unregistered_line
        return unless @session_id

        "Plastic: #{Doctor.unregistered(@session_id, @harness)}; run plastic doctor --harness with one of #{Harnesses.names.join(", ")}."
      end
    end
  end
end
