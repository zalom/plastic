# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "installation"
require_relative "release_update"

module Plastic
  module Workflows
    # Syncs a newer running package into the home for the registered agents.
    # When the running package is not newer, activates the newest release of
    # the chosen channel, or of the active release's channel, and syncs its
    # files into the home. With no release activated yet, names the installer
    # command that installs one.
    class UpdatePlastic < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :newer, :synced, :active, :release, :activated

      read "check whether the running package is newer" do |context|
        context[:newer] = Installation.of(context).newer?
      end

      step "sync the newer package into the home", done: ->(context) { !context.newer || context.synced } do |context|
        installation = Installation.of(context)
        agents = installation.installed_agents
        lines = Installation.capture { installation.install(agents, reinstall: true, force: false) }
        lines.each { |line| context.print(line) }
        context[:synced] = true
      end

      read "find a newer release on the chosen channel" do |context|
        newest_release(context) unless context.newer
      end

      step "activate the newer release", done: ->(context) { context.release.nil? || context.activated } do |context|
        context[:activated] = ReleaseUpdate.of(context).activate(context.release)
      end

      outcome :done, if: ->(context) { context.synced }, offers: "plastic version", because: "the home holds Plastic %{to}"
      outcome :activated, if: ->(context) { context.activated }, offers: "plastic version",
        because: "Plastic %{activated} is active and the home holds its files"
      outcome :current, if: ->(context) { context.active }, offers: "plastic version",
        because: "Plastic %{active} is the newest release on its channel"
      outcome :fetch, offers: "plastic update", because: "run the installer command above, then update again"

      def self.newest_release(context)
        release = ReleaseUpdate.of(context)
        context[:active] = release.active_version
        context.active ? newer_release(context, release) : fetch_hint(context)
      end

      def self.newer_release(context, release)
        release.notices.each { |notice| context.print(notice) }
        context[:release] = release.newer_release(context.channel)
      end

      def self.fetch_hint(context)
        channel = context.channel || ReleaseUpdate::CHANNELS.key(Installation.of(context).channel)
        context.row("run:", Installation.fetch_command("PLASTIC_CHANNEL=#{channel}"))
      end
    end
  end
end
