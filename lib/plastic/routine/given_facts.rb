# frozen_string_literal: true

module Plastic
  class Routine < CLI::Command
    # The facts a tool hands its workflows from what only the shell knows.
    module GivenFacts
      # None, until the tool defines them: a name and the value every call of the tool carries.
      def given_facts = {}
    end
  end
end
