# frozen_string_literal: true

require_relative "../init"
require_relative "../../../code_workflow"
require_relative "../../../cli/screen"
require_relative "../../../harnesses"

module Plastic
  module Workflows
    module Code
      class Init
        # Reads the person's answer against the installed harnesses and the
        # sync of images and videos, every one of them picked at the start.
        class Choose < CodeWorkflow
          clear_declarations
          summary "Finds the harnesses on this machine and chooses which ones to set up, and whether a sync keeps images and videos."

          MEDIA = "sync images and videos"

          sets :found, :picked, :harnesses, :media

          # The found harnesses, then the sync of images and videos; none when no harness is found.
          def self.choices(names)
            labels = names.empty? ? [] : [*names, MEDIA]
            labels.map { |label| CLI::Screen::Choice.new(label:, chosen: true) }
          end

          read "find the installed harnesses and read the person's answer" do |context|
            found = Harnesses.found_in(context.scope).map(&:name)
            result = CLI::Screen::Answer.new(Choose.choices(found)).call(context.answer) if found.any?
            labels = result.is_a?(CLI::Screen::Chosen) ? result.labels : []
            context[:found] = found
            context[:picked] = labels - [MEDIA]
            context[:media] = labels.include?(MEDIA)
            context[:harnesses] = context.picked.join(", ")
          end

          outcome :none, if: ->(context) { context.found.empty? }, offers: "plastic init",
            because: "no registered harness was found: no settings folder in the home and no program on the PATH; install one, then run this again"
          outcome :left, if: ->(context) { context.picked.empty? }, offers: "plastic init",
            because: "the person left with no change"
          outcome :chosen, offers: "plastic init %{answer}", because: "install Plastic into %{harnesses}"
        end
      end
    end
  end
end
