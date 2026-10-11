# frozen_string_literal: true

module Plastic
  module Harnesses
    # What Plastic knows about one harness: the variables its tool shells
    # carry, the folder its transcripts live in, its process name, an event
    # field only it writes, the hook command of each event, its settings file
    # under the home, and the doctor that checks it.
    Harness = Data.define(:name, :session_variables, :transcript, :process, :event_field, :events, :settings, :doctor) do
      def wrote?(event) = event.key?(event_field)

      def session(env) = session_variables.map { |variable| env[variable].to_s.strip }.find { |text| !text.empty? }

      def transcribed?(path) = path.match?(Regexp.new(transcript))
    end
  end
end
