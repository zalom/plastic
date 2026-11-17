# frozen_string_literal: true

require "shellwords"
require_relative "check"
require_relative "version_record"
require_relative "database_check"
require_relative "instruction_line"
require_relative "store_backups"
require_relative "home_ignore"
require_relative "../wiring"
require_relative "../workflows/installation_health"

module Plastic
  module Doctor
    class Core
      SQLITE = lambda do
        require "sqlite3"
        SQLite3::VERSION
      end
      SCHEMA = Graph::Schema
      STORE = SCHEMA.store
      PLASTIC_LINE = /PLASTIC\.md/

      def self.store_problem(folder)
        problems = STORE.filter_map { |key| DatabaseCheck.new(File.join(folder, SCHEMA.file(key)), key).problem }
        problems.join("; ") unless problems.empty?
      end

      def self.agents(slug, path)
        file = File.join(path, "AGENTS.md")
        Check.new("AGENTS.md #{slug}:", "#{file} names PLASTIC.md", "add a line naming ~/.plastic/PLASTIC.md to #{file}")
          .judged(InstructionLine.new(file, PLASTIC_LINE).problem)
      end

      def initialize(scope, running:, now:, loader: SQLITE)
        @scope = scope
        @running = running
        @loader = loader
        @now = now
      end

      def checks = [version, *release, sqlite, machine_database, *former_database, config_file, home_ignore, global_store, plastic_md, *scope.projects.flat_map { |slug, path| project(slug, path) }, *backups]

      private

      attr_reader :scope, :running, :loader, :now

      def home = scope.plastic_home

      def version = VersionRecord.new(File.join(home, "VERSION"), running).check("version:", install: "plastic install")

      def release = Workflows::InstallationHealth.at(scope).parts.map { |part| Check.from(part) }

      def sqlite
        Check.ok("sqlite3 gem:", "loads, version #{loader.call}")
      rescue LoadError => error
        Check.finding("sqlite3 gem:", "does not load: #{error.message}", "gem install sqlite3")
      end

      def machine_database
        key = (SCHEMA.databases.keys - STORE - SCHEMA.derived).first
        file = SCHEMA.file(key)
        Check.new("#{file}:", "every table present", "plastic install --reinstall").judged(DatabaseCheck.new(File.join(home, file), key).problem)
      end

      def former_database
        path = File.join(home, "local.db")
        return [] unless File.exist?(path)

        return [Check.finding("local.db:", "#{path} is not migrated", "plastic update")] unless File.exist?(File.join(home, "plastic.db"))

        [Check.finding("local.db:", "#{path} is left beside plastic.db", "move local.db out of #{home}; plastic update keeps a copy of it in backups/")]
      end

      def config_file
        line = Wiring.store(home).problem
        return Check.ok("config.yml:", "matches the settings rows") unless line

        Check.finding("config.yml:", line, Config::Store::REPAIR)
      end

      def home_ignore = HomeIgnore.new(home).check

      def global_store
        path = File.join(home, "stores", "global")
        Check.new("global store:", path, "plastic install --reinstall").judged(File.directory?(path) ? nil : "#{path} is missing")
      end

      def plastic_md
        path = File.join(home, "PLASTIC.md")
        Check.new("PLASTIC.md:", path, "plastic install --reinstall").judged(File.file?(path) ? nil : "#{path} is missing")
      end

      def backups = [Scope::GLOBAL, *scope.projects.keys].map { |slug| StoreBackups.new(File.join(home, "stores", slug), slug, now:).check }

      def project(slug, path) = [store(slug, path), Core.agents(slug, path)]

      def store(slug, path)
        Check.new("store #{slug}:", "#{STORE.size} databases, every table present", "plastic project new #{slug} #{Shellwords.escape(path)}")
          .judged(Core.store_problem(File.join(home, "stores", slug)))
      end
    end
  end
end
