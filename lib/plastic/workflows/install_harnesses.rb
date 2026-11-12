# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "../harnesses"
require_relative "installation"
require_relative "installation_hooks"

module Plastic
  module Workflows
    # Checks the machine, copies the core files on a home that has none,
    # and installs Plastic into each picked harness.
    class InstallHarnesses < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :usable, :broken, :installed, :checked

      read "check this machine and the harness settings files" do |context|
        usable, messages = Installation.of(context).preflight
        messages.each { |line| context.print(line) }
        context[:usable] = usable
        context[:broken] = InstallationHooks.new(home: context.scope.home).unreadable
      end

      gate "this machine cannot run Plastic; see above", stops: :failure, pass: ->(context) { context.usable }
      gate "%{broken} is not valid JSON; nothing was changed. Fix the file and run this again", stops: :failure,
        pass: ->(context) { context.broken.nil? }

      step "install Plastic into the picked harnesses", done: ->(context) { !context.installed.nil? } do |context|
        installation = Installation.of(context)
        keys = context.picked.map { |name| Harnesses.fetch(name).installer }
        Installation.capture { installation.wire(keys) }.each { |line| context.print(line) }
        context[:installed] = installation.version
        context[:checked] = context.picked.first
      end

      outcome :done, offers: "plastic doctor --harness %{checked}", because: "Plastic %{installed} is installed into %{harnesses}"
    end
  end
end
