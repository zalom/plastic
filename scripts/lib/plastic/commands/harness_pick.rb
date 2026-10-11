# frozen_string_literal: true

require_relative "../cli/screen"

module Plastic
  module Commands
    # The person's pick of harnesses for a command that takes the answer as
    # its argument. With no answer the command asks on the choice screen; with
    # no terminal the screen prints the numbered list and the call stops.
    # See docs/help/choice-screen.md.
    module HarnessPick
      def call
        answer = parsed[:answer] ||= answered_on_screen
        super if answer
      end

      private

      def answered_on_screen
        command = self.class
        choices = command.choices(scope)
        return CLI::Screen::Answer::LEAVE if choices.empty?

        CLI::Screen.for(environment, output:).answer(command::QUESTION, choices, command: screen_command)
      end

      def screen_command = ["plastic", self.class::NAME, *("--dry-run" if parsed[:dry_run])].join(" ")
    end
  end
end
