# frozen_string_literal: true

module Plastic
  module Harnesses
    # What Plastic knows about one harness: the variables its tool shells
    # carry, the folder its transcripts live in, its process name, an event
    # field only it writes, the hook command of each event, its folder and
    # settings file under the home, the doctor that checks it, and the
    # installer that writes Plastic into it. A field a harness has no value
    # for is nil or empty, and what reads it skips it.
    Harness = Data.define(:name, :session_variables, :transcript, :process, :event_field, :events, :folder, :settings,
      :doctor, :installer) do
      def wrote?(event) = event.key?(event_field)

      def session(env) = session_variables.map { |variable| env[variable].to_s.strip }.find { |text| !text.empty? }

      def transcribed?(path) = transcript && path.match?(Regexp.new(transcript))

      # Installed when its settings folder is in the home or its program is on the PATH.
      def found?(home:, path:) = File.directory?(File.join(home, folder)) || program?(path)

      private

      def program?(path) = process && path.split(File::PATH_SEPARATOR).any? { |dir| File.executable?(File.join(dir, process)) }
    end
  end
end
