# frozen_string_literal: true

require_relative "../routine"
require_relative "../cli/screen"
require_relative "../harnesses"

module Plastic
  module Commands
    # Finds the installed harnesses, shows them on the choice screen with
    # every found one picked, and installs Plastic into each one the person
    # picks. See docs/help/choice-screen.md.
    class Init < Routine
      opens_no_store

      QUESTION = "Which harnesses should Plastic be installed into?"

      argument :answer, label: "ANSWER", text: "the person's answer to the numbered list", optional: true

      workflow :code_choose_harnesses do
        on :none, next: :noop
        on :left, next: :noop
        on :chosen, next: :code_install_harnesses
      end
      workflow :code_install_harnesses, next: :noop

      def self.choices(scope) = Harnesses.found_in(scope).map { |harness| CLI::Screen::Choice.new(label: harness.name, chosen: true) }

      def call
        answer = parsed[:answer] ||= answered_on_screen
        super if answer
      end

      private

      def answered_on_screen
        choices = self.class.choices(scope)
        return CLI::Screen::Answer::LEAVE if choices.empty?

        CLI::Screen.for(environment, output:).answer(QUESTION, choices, command: "plastic init")
      end
    end
  end
end
