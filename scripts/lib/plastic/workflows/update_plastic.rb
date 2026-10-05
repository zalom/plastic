# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "installation"

module Plastic
  module Workflows
    # Syncs a newer running package into the home for the registered agents.
    # When the running package is not newer, names the installer command
    # that fetches the newest release of its channel, since Plastic downloads
    # nothing itself.
    class UpdatePlastic < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :newer, :synced

      read "check whether the running package is newer" do |context|
        installation = Installation.of(context)
        context[:newer] = installation.newer?
        context.row("run:", Installation.fetch_command("PLASTIC_CHANNEL=#{installation.channel}")) unless context.newer
      end

      step "sync the newer package into the home", done: ->(context) { !context.newer || context.synced } do |context|
        installation = Installation.of(context)
        agents = installation.installed_agents
        lines = Installation.capture { installation.install(agents, reinstall: true, force: false) }
        lines.each { |line| context.print(line) }
        context[:synced] = true
      end

      outcome :done, if: ->(context) { context.synced }, offers: "plastic version", because: "the home holds Plastic %{to}"
      outcome :fetch, offers: "plastic update", because: "run the installer command above, then update again"
    end
  end
end
