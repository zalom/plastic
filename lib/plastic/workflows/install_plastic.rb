# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "installation"
require_relative "installation_hooks"

module Plastic
  module Workflows
    # Checks the machine, then copies the core files into the home. A
    # reinstall also syncs the harnesses Plastic is installed into.
    class InstallPlastic < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :usable, :broken, :present, :installed

      read "check this machine and the harness settings files" do |context|
        installation = Installation.of(context)
        usable, messages = installation.preflight
        messages.each { |line| context.print(line) }
        context[:usable] = usable
        context[:broken] = InstallationHooks.new(home: context.scope.home).unreadable
        context[:present] = installation.installed?
      end

      gate "this machine cannot run Plastic; see above", stops: :failure, pass: ->(context) { context.usable }
      gate "%{broken} is not valid JSON; nothing was changed. Fix the file and run this again", stops: :failure,
        pass: ->(context) { context.broken.nil? }
      gate "Plastic is already installed; run plastic init to add a harness, or pass --reinstall to sync the files again",
        stops: :refusal, pass: ->(context) { context.reinstall || !context.present }

      step "install the core files", done: ->(context) { !context.installed.nil? } do |context|
        installation = Installation.of(context)
        keys = context.reinstall ? installation.synced : []
        lines = Installation.capture { installation.install(keys, reinstall: context.reinstall, force: context.force) }
        lines.each { |line| context.print(line) }
        context[:installed] = installation.version
      end

      outcome :done, offers: "plastic init", because: "Plastic %{installed} is installed"
    end
  end
end
