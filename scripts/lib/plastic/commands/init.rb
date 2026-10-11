# frozen_string_literal: true

require_relative "../routine"
require_relative "../harnesses"
require_relative "harness_pick"

module Plastic
  module Commands
    # Finds the installed harnesses, shows them on the choice screen with
    # every found one picked, and installs Plastic into each one the person
    # picks. See docs/help/choice-screen.md.
    class Init < Routine
      include HarnessPick

      opens_no_store

      NAME = "init"
      QUESTION = "Which harnesses should Plastic be installed into?"

      argument :answer, label: "ANSWER", text: "the person's answer to the numbered list", optional: true

      workflow :code_choose_harnesses do
        on :none, next: :noop
        on :left, next: :noop
        on :chosen, next: :code_install_harnesses
      end
      workflow :code_install_harnesses, next: :noop

      def self.choices(scope) = Harnesses.found_in(scope).map { |harness| CLI::Screen::Choice.new(label: harness.name, chosen: true) }
    end
  end
end
