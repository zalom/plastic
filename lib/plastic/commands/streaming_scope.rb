# frozen_string_literal: true

require_relative "../cli/scope"

module Plastic
  module Commands
    # The store scope of a call that may print lines while it works. `live`
    # is the sink each line goes to, and does nothing when the call did not
    # ask for the lines.
    class StreamingScope < CLI::Scope
      QUIET = ->(_line) {}

      # The scope of `slug`; its lines go to `output` when one is given.
      def self.for(environment, slug:, output:)
        new(env: environment.env, home: environment.home, slug:, directory: environment.directory,
          live: output ? output.method(:raw) : QUIET)
      end

      attr_reader :live

      def initialize(live:, **scope)
        super(**scope)
        @live = live
      end
    end
  end
end
