# frozen_string_literal: true

require "shellwords"
require_relative "check"
require_relative "version_record"
require_relative "database_check"
require_relative "retrieval_marker"
require_relative "instruction_line"
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

      def initialize(scope, running:, loader: SQLITE)
        @scope = scope
        @running = running
        @loader = loader
      end

      def checks = [version, *release, sqlite, machine_database, global_store, plastic_md, *scope.projects.flat_map { |slug, path| project(slug, path) }]

      private

      attr_reader :scope, :running, :loader

      def home = scope.plastic_home

      def version = VersionRecord.new(File.join(home, "VERSION"), running).check("version:", install: "plastic install")

      def release = Workflows::InstallationHealth.at(scope).parts.map { |part| Check.from(part) }

      def sqlite
        Check.ok("sqlite3 gem:", "loads, version #{loader.call}")
      rescue LoadError => error
        Check.finding("sqlite3 gem:", "does not load: #{error.message}", "gem install sqlite3")
      end

      def machine_database
        key = (SCHEMA.databases.keys - STORE).first
        file = SCHEMA.file(key)
        Check.new("#{file}:", "every table present", "plastic install --reinstall").judged(DatabaseCheck.new(File.join(home, file), key).problem)
      end

      def global_store
        path = File.join(home, "stores", "global")
        Check.new("global store:", path, "plastic install --reinstall").judged(File.directory?(path) ? marker_problem(path) : "#{path} is missing")
      end

      def plastic_md
        path = File.join(home, "PLASTIC.md")
        Check.new("PLASTIC.md:", path, "plastic install --reinstall").judged(File.file?(path) ? nil : "#{path} is missing")
      end

      def project(slug, path) = [store(slug, path), Core.agents(slug, path)]

      def store(slug, path)
        Check.new("store #{slug}:", "#{STORE.size} databases, every table present", "plastic project new #{slug} #{Shellwords.escape(path)}")
          .judged(store_problem(File.join(home, "stores", slug)))
      end

      def store_problem(folder) = Core.store_problem(folder) || marker_problem(folder)

      def marker_problem(folder) = RetrievalMarker.new(home, folder).problem
    end
  end
end
