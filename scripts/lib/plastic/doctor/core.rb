# frozen_string_literal: true

require "shellwords"
require_relative "check"
require_relative "version_record"
require_relative "database_check"
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
      PLASTIC_LINE = /PLASTIC\.md/

      def initialize(scope, running:, loader: SQLITE)
        @scope = scope
        @running = running
        @loader = loader
      end

      def checks = [version, *release, sqlite, machine_database, plastic_md, *scope.projects.flat_map { |slug, path| project(slug, path) }]

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
        key = (SCHEMA.databases.keys - SCHEMA.store).first
        file = SCHEMA.file(key)
        Check.of("#{file}:", DatabaseCheck.new(File.join(home, file), key).problem, detail: "every table present", repair: "plastic next")
      end

      def plastic_md
        path = File.join(home, "PLASTIC.md")
        Check.of("PLASTIC.md:", (File.file?(path) ? nil : "#{path} is missing"), detail: path, repair: "plastic install --reinstall")
      end

      def project(slug, path) = [store(slug, path), agents(slug, path)]

      def store(slug, path)
        folder = File.join(home, "stores", slug)
        problems = SCHEMA.store.filter_map { |key| DatabaseCheck.new(File.join(folder, SCHEMA.file(key)), key).problem }
        Check.of("store #{slug}:", problems.empty? ? nil : problems.join("; "), detail: "#{SCHEMA.store.size} databases, every table present",
          repair: "plastic project new #{slug} #{Shellwords.escape(path)}")
      end

      def agents(slug, path)
        file = File.join(path, "AGENTS.md")
        Check.of("AGENTS.md #{slug}:", InstructionLine.new(file, PLASTIC_LINE).problem, detail: "#{file} names PLASTIC.md",
          repair: "add a line naming ~/.plastic/PLASTIC.md to #{file}")
      end
    end
  end
end
