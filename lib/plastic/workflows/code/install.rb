# frozen_string_literal: true

require_relative "../../code_workflow"
require_relative "../installation"
require_relative "../../doctor/installation_hooks"

module Plastic
  module Workflows
    module Code
      # Copies the core files into the home. A reinstall also syncs the
      # harnesses Plastic is installed into.
      class Install < CodeWorkflow
        clear_declarations
        summary "Copies the core files of Plastic into the home."

        sets :broken, :present, :installed

        read "check the harness settings files" do |context|
          installation = Installation.of(context)
          context[:broken] = Plastic::Doctor::InstallationHooks.new(home: context.scope.home).unreadable
          context[:present] = installation.installed?
        end

        gate "%{broken} is not valid JSON; nothing was changed. Fix the file and run this again", stops: :failure,
          pass: ->(context) { context.broken.nil? }
        gate "Plastic is already installed; run plastic init to add a harness, or pass --reinstall to sync the files again",
          stops: :refusal, pass: ->(context) { context.reinstall || !context.present }

        step "install the core files", done: ->(context) { !context.installed.nil? },
          changes: { home: "The core files are copied into the Plastic home" } do |context|
          installation = Installation.of(context)
          keys = context.reinstall ? installation.synced : []
          lines = Installation.capture { installation.install(keys) }
          lines.each { |line| context.print(line) }
          context[:installed] = installation.version
        end

        outcome :done, offers: "plastic init", because: "Plastic %{installed} is installed"
      end
    end
  end
end
