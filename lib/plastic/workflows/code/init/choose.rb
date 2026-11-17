# frozen_string_literal: true

require_relative "../../../screen_choice"
require_relative "../../../answer"
require_relative "../init"
require_relative "../../../code_workflow"
require_relative "../../../harnesses"
require_relative "../../../wiring"

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

          # The found harnesses, all picked, then the sync of images and videos,
          # picked unless the home turned it off; none when no harness is found.
          def self.choices(scope)
            names = Harnesses.found_in(scope).map(&:name)
            return [] if names.empty?

            [*names.map { |name| Choice.new(label: name, chosen: true) }, Choice.new(label: MEDIA, chosen: media?(scope))]
          end

          # Picked until the setting sync.media turns the sync of images and videos off.
          def self.media?(scope) = !Plastic::Config::FALSE_VALUES.include?(Plastic::Wiring.config(scope.plastic_home).overrides.dig("sync", "media"))

          read "find the installed harnesses and read the person's answer" do |context|
            choices = Choose.choices(context.scope)
            found = choices.map(&:label) - [MEDIA]
            result = Answer.new(choices).call(context.answer) if found.any?
            labels = result.is_a?(Chosen) ? result.labels : []
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
