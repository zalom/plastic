# frozen_string_literal: true

require "forwardable"
require "tmpdir"
require_relative "../config/upgrade"
require_relative "home_ignore"
require_relative "../installations"
require_relative "../graph"
require_relative "../store_layout"
require_relative "advisor_migration"
require_relative "agent_run"
require_relative "agent_set"
require_relative "bootstrap"
require_relative "core_files"
require_relative "distribution"
require_relative "ledger"
require_relative "package"
require_relative "package_version"
require_relative "release_feed"
require_relative "results"

module Plastic
  module Installations
    # Installs a package into the Plastic home and into the agents the person
    # chose: the core files, the first-install store, then one transaction for
    # each agent, the record of what was installed, the ledger and the report.
    class Installer
      LEDGER_ACTIONS = { install: "install", update: "reinstall" }.freeze

      extend Forwardable

      attr_reader :package

      def_delegator :package, :root, :package_root
      def_delegator :package, :home, :plastic_home
      def_delegator :package, :version
      def_delegator :@agents, :agents
      def_delegator :@agents, :config, :agent_config
      def_delegator :@agents, :installed_keys, :installed_agents

      def initialize(package, **seams)
        @package = package
        @agents = AgentSet.new(seams.fetch(:agents, AgentSet::DEFAULTS))
        @distribution = seams.except(:agents)
      end

      def installed? = File.exist?(File.join(plastic_home, "VERSION"))

      def installed_version = installed? ? File.read(File.join(plastic_home, "VERSION")).strip : nil

      def channel = ReleaseFeed.channel_of(version)

      def newer? = ReleaseFeed.newer?(version, installed_version)

      def core_files = CoreFiles.new(package_root, status_line: package.choices.statusline?).call

      def install_agents(selected:, statusline: nil, already_registered: [])
        kind = installed? ? :update : :install
        prepare(kind)
        results = sync(selected, statusline) + already_registered.map { |key| skipped(key) }
        log(results, LEDGER_ACTIONS.fetch(kind))
        Results.new(version).print(results, kind)
        results
      end

      private

      def sync(selected, statusline)
        results = selected.map { |key| AgentRun.new(@agents, package, statusline).call(key) }
        Installations.record(self, results.select { |result| result[:success] }.map { |result| result[:key] })
        results
      end

      def prepare(kind)
        Distribution.new(package, **@distribution).public_send(kind)
        prepare_config_import
        migrate_databases
        (kind == :install) ? Bootstrap.new(plastic_home).call : Graph.create(home: plastic_home, store: StoreLayout::GLOBAL)
        print_config
      end

      def print_config
        HomeIgnore.new(plastic_home).apply
        line = package.settings.store.print_once
        puts "   #{line}" if line
      end

      def prepare_config_import
        state = Graph::Database::Local.new(plastic_home).schema_state
        return if state && !state.pending.include?(Graph::MIGRATIONS.baseline(:home))

        AdvisorMigration.file(File.join(plastic_home, "config.yml"))
        report_config_upgrade
      end

      def migrate_databases
        Graph::SchemaRunner.new(home: plastic_home, now: package.clock.now, selection: package.settings.selection, released: package.settings.released).call.lines.each { |line| puts "   #{line}" }
      end

      def report_config_upgrade
        Config::Upgrade.new(File.join(plastic_home, "config.yml")).call.each do |old, new|
          puts "   config.yml: the settings for #{old} now apply to #{new}."
        end
      end

      def skipped(key) = { agent: agent_config(key)[:name], success: false, skipped: true }

      def log(results, action)
        synced = results.filter_map { |result| result[:key] if result[:success] }
        Ledger.new(plastic_home, clock: package.clock).append_run(version, action, synced)
      end
    end
  end
end
