# frozen_string_literal: true

require_relative "../routine"
require_relative "../installations"
require_relative "harness_pick"

module Plastic
  module Commands
    # Shows the harnesses Plastic is installed into or found in, with every
    # recorded one picked, and removes what the record of each picked one
    # lists. The home and its stores stay. See docs/help/choice-screen.md.
    class Uninstall < Routine
      include HarnessPick

      opens_no_store

      NAME = "uninstall"
      QUESTION = "Which harnesses should Plastic be removed from?"

      argument :answer, label: "ANSWER", text: "the person's answer to the numbered list", optional: true
      option :dry_run, switch: "--dry-run", default: false, text: "list what would change and change nothing"

      workflow :code_choose_installations do
        on :none, next: :noop
        on :left, next: :noop
        on :chosen, next: :code_preview_uninstall
      end
      workflow :code_preview_uninstall do
        on :done, next: :noop
        on :continue, next: :code_uninstall_plastic
      end
      workflow :code_uninstall_plastic, next: :noop

      def self.choices(scope)
        recorded = Installations.recorded(scope.plastic_home)
        Installations.listed(scope).map { |name| CLI::Screen::Choice.new(label: name, chosen: recorded.include?(name)) }
      end
    end
  end
end
