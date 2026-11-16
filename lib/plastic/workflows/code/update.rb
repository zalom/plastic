# frozen_string_literal: true

require_relative "../../code_workflow"
require_relative "../installation"
require_relative "../release_command"
require_relative "../release_update"
require_relative "../schema_migration"

module Plastic
  module Workflows
    module Code
      # Syncs a newer running package into the home for the registered agents.
      # When the running package is not newer, downloads and checks the newest
      # release of the chosen channel, or of the active release's channel, and
      # names the command that installs it. With no release installed yet,
      # names install.sh.
      class Update < CodeWorkflow
        clear_declarations
        summary "Downloads and checks the newest release and names the command that installs it."

        sets :newer, :synced, :active, :release, :downloaded, :command, :migrated

        read "check whether the running package is newer" do |context|
          installation = Installation.of(context)
          context[:newer] = installation.installed? && installation.newer?
        end

        step "sync the newer package into the home", done: ->(context) { !context.newer || context.synced },
          changes: { home: "The newer package is synced into the Plastic home", harness: "The installed agents are refreshed" } do |context|
          installation = Installation.of(context)
          agents = installation.installed_agents
          lines = Installation.capture { installation.install(agents) }
          lines.each { |line| context.print(line) }
          context[:synced] = true
        end

        step "bring the databases to the newest layout", done: ->(context) { !context.migrated.nil? },
          changes: { databases: "Every database behind its sequence is migrated after a backup of its store", backups: "A migration backup is written for each store that moves" } do |context|
          context[:migrated] = SchemaMigration.bring_current(context).migrated
        end

        read "find a newer release on the chosen channel" do |context|
          newest_release(context) unless context.newer
        end

        step "download the newer release", done: ->(context) { context.release.nil? || context.downloaded },
          changes: { home: "The newer release is downloaded and made the active release" } do |context|
          ReleaseUpdate.of(context).download(context.release)
          context[:command] = ReleaseCommand.of(context.scope).install(context.active, context.release)
          context[:downloaded] = true
        end

        outcome :done, if: ->(context) { context.synced }, offers: "plastic version", because: "the home holds Plastic %{to}"
        outcome :downloaded, if: ->(context) { context.downloaded }, offers: "%{command}",
          because: "Plastic %{release} is downloaded and checked; this command installs it"
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
          context.row("run:", Installation.fetch_command)
        end
      end
    end
  end
end
