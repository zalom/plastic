# frozen_string_literal: true

require_relative "../scope"
require_relative "screen"

module Plastic
  class CLI
    # The store scope of a call that may ask the person to pick. The scope
    # reaches every step through the context, so the screen goes with it.
    class AskingScope < Scope
      # The scope of `slug`, asking through the environment's streams and the output.
      def self.for(environment, slug:, output:)
        new(env: environment.env, home: environment.home, slug:, directory: environment.directory,
          screen: CLI::Screen.for(environment, output:))
      end

      attr_reader :screen

      def initialize(screen:, **scope)
        super(**scope)
        @screen = screen
      end
    end
  end
end
