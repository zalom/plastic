# frozen_string_literal: true

require_relative "../../code_workflow"
require_relative "../../harnesses"
require_relative "../installation"
require_relative "../../doctor/installation_hooks"
require_relative "../../cli/wiring"

module Plastic
  module Workflows
    module Code
      # Copies the core files on a home that has none, and installs Plastic
      # into each picked harness.
      class Init < CodeWorkflow
        clear_declarations
        summary "Installs Plastic into each chosen harness."

        sets :broken, :installed, :checked

        read "check the harness settings files" do |context|
          context[:broken] = Plastic::Doctor::InstallationHooks.new(home: context.scope.home).unreadable
        end

        gate "%{broken} is not valid JSON; nothing was changed. Fix the file and run this again", stops: :failure,
          pass: ->(context) { context.broken.nil? }

        step "install Plastic into the picked harnesses", done: ->(context) { !context.installed.nil? },
          changes: { home: ["Plastic is installed into the Plastic home", "Whether a sync keeps images and videos is written to the settings rows"],
                     harness: "The instructions and hooks of each picked harness are written" } do |context|
          installation = Installation.of(context)
          keys = context.picked.map { |name| Harnesses.fetch(name).installer }
          Installation.capture { installation.wire(keys) }.each { |line| context.print(line) }
          Plastic::Wiring.config(context.scope.plastic_home, clock: context.clock).set("sync.media", context.media)
          context[:installed] = installation.version
          context[:checked] = context.picked.first
        end

        outcome :done, offers: "plastic doctor --harness %{checked}", because: "Plastic %{installed} is installed into %{harnesses}"
      end
    end
  end
end
