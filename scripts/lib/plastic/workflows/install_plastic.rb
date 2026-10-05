# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "installation"

module Plastic
  module Workflows
    # Checks the machine, then copies the core files into the home and
    # registers the chosen agents. Agents already registered are skipped
    # unless the call asks for a reinstall.
    class InstallPlastic < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :usable, :pending, :installed

      read "check this machine and the registered agents" do |context|
        installation = Installation.of(context)
        usable, messages = installation.preflight
        messages.each { |line| context.print(line) }
        context[:usable] = usable
        context[:pending] = installation.unregistered(Installation.selected(context))
      end

      gate "this machine cannot run Plastic; see above", stops: :failure, pass: ->(context) { context.usable }
      gate "Plastic is already installed for every chosen agent; pass --reinstall to sync the files again",
        stops: :refusal, pass: ->(context) { context.reinstall || context.pending.any? }

      step "install the core files and register the agents", done: ->(context) { !context.installed.nil? } do |context|
        installation = Installation.of(context)
        selected = Installation.selected(context)
        lines = Installation.capture { installation.install(selected, reinstall: context.reinstall, force: context.force) }
        lines.each { |line| context.print(line) }
        context[:installed] = installation.version
      end

      outcome :done, offers: "plastic version", because: "Plastic %{installed} is installed"
    end
  end
end
