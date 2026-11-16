# frozen_string_literal: true

require_relative "../routine"
require_relative "../harnesses"
require_relative "../cli/harness_pick"
require_relative "../workflows/code/init/choose"

module Plastic
  module Commands
    # Finds the installed harnesses, shows them on the choice screen with
    # every found one picked and the sync of images and videos after them,
    # and installs Plastic into each one the person picks. See
    # docs/help/choice-screen.md.
    class Init < Routine
      include CLI::HarnessPick

      opens_no_store

      NAME = "init"
      QUESTION = "Which harnesses should Plastic be installed into, and should a sync keep images and videos?"

      argument :answer, label: "ANSWER", text: "the person's answer to the numbered list", optional: true

      workflow :code_choose_harnesses do
        on :none, next: :noop
        on :left, next: :noop
        on :chosen, next: :code_install_harnesses
      end
      workflow :code_install_harnesses, next: :noop

      def self.choices(scope) = Workflows::Code::Init::Choose.choices(scope)
    end
  end
end
