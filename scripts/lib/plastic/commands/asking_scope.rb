# frozen_string_literal: true

require_relative "../cli/scope"
require_relative "../cli/dialog"

module Plastic
  module Commands
    # The store scope of a call that may ask the person a question. The scope
    # reaches every step through the context, so the dialog goes with it.
    class AskingScope < CLI::Scope
      # The scope of `slug`, asking through the environment's input and the output.
      def self.for(environment, slug:, output:)
        new(env: environment.env, home: environment.home, slug:, directory: environment.directory,
          dialog: CLI::Dialog.new(input: environment.input, output:))
      end

      attr_reader :dialog

      def initialize(dialog:, **scope)
        super(**scope)
        @dialog = dialog
      end
    end
  end
end
