# frozen_string_literal: true

require "tmpdir"
require_relative "../config/upgrade"
require_relative "../installations"
require_relative "../graph"
require_relative "../store_layout"
require_relative "advisor_migration"
require_relative "agent_set"
require_relative "bootstrap"
require_relative "claude_install"
require_relative "codex_install"
require_relative "core_files"
require_relative "distribution"
require_relative "hermes_install"
require_relative "ledger"
require_relative "package"
require_relative "package_version"
require_relative "release_feed"
require_relative "results"
require_relative "skill_copy"
require_relative "transaction"

module Plastic
  module Installations
    # Installs a package into the Plastic home and into the agents the person
    # chose: the core files, the first-install store, then one transaction for
    # each agent, the record of what was installed, the ledger and the report.
    class Installer
      INSTALLS = { "claude" => ClaudeInstall, "codex" => CodexInstall, "hermes" => HermesInstall }.freeze

      attr_reader :package_root, :plastic_home

      def initialize(package_root:, plastic_home:, version: nil, agents: AgentSet::DEFAULTS, tmp_dirs: [Dir.tmpdir, "/tmp"].uniq)
        @package_root = package_root
        @plastic_home = plastic_home
        @version = version
        @agents = AgentSet.new(agents)
        @tmp_dirs = tmp_dirs
      end

      def version = @version ||= PackageVersion.new(package_root).call

      def agents = @agents.agents

      def agent_config(key) = @agents.config(key)

      def installed_agents = @agents.installed_keys

      def installed? = File.exist?(File.join(plastic_home, "VERSION"))

      def installed_version = installed? ? File.read(File.join(plastic_home, "VERSION")).strip : nil

      def channel = ReleaseFeed.channel_of(version)

      def newer? = ReleaseFeed.newer?(version, installed_version)

      def core_files = CoreFiles.new(package_root).call

      def install_agents(selected:, ledger_action: nil, statusline: nil, already_registered: [])
        fresh = !installed?
        prepare(fresh)
        results = sync(selected, statusline) + already_registered.map { |key| skipped(key) }
        log(results, ledger_action || (fresh ? "install" : "reinstall"))
        Results.new(version).print(results, fresh ? :install : :update)
        results
      end

      private

      def package = Package.new(package_root, plastic_home, version)

      def sync(selected, statusline)
        results = selected.map { |key| agent(key, statusline) }
        Installations.record(self, results.select { |result| result[:success] }.map { |result| result[:key] })
        results
      end

      def prepare(fresh)
        Distribution.new(package, tmp_dirs: @tmp_dirs).call(fresh ? :install : :update)
        fresh ? Bootstrap.new(plastic_home).call : Graph.create(home: plastic_home, store: StoreLayout::GLOBAL)
        AdvisorMigration.file(File.join(plastic_home, "config.yml"))
        report_config_upgrade
      end

      def report_config_upgrade
        Config::Upgrade.new(File.join(plastic_home, "config.yml")).call.each do |old, new|
          puts "   config.yml: the settings for #{old} now apply to #{new}."
        end
      end

      def agent(key, statusline)
        record = @agents.record(key)
        return { agent: key, success: false, reason: "Unknown agent", key: key } unless record

        Transaction.new(plastic_home, record, roots_of(record)).call { install_for(key, record, statusline).call }.merge(key: key)
      end

      def roots_of(record) = record.roots(SkillCopy.new(package_root, plastic_home).fragments)

      def install_for(key, record, statusline)
        kind = INSTALLS.fetch(key)
        (key == "claude") ? kind.new(package, record, statusline:) : kind.new(package, record)
      end

      def skipped(key) = { agent: agent_config(key)[:name], success: false, skipped: true }

      def log(results, action)
        ledger = Ledger.new(plastic_home)
        synced = results.select { |result| result[:success] && result[:key] }
        synced.each { |result| ledger.append(version, action, harness: result[:key]) }
        ledger.append(version, action) if synced.empty?
      end
    end
  end
end
