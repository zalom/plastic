# frozen_string_literal: true

require "fileutils"
require_relative "files"
require_relative "../graph"
require_relative "../store_layout"

module Plastic
  module Installations
    # The first install of a Plastic home: the config, the projects file, the
    # agent instructions and the global store with its databases. A home that
    # already holds a store, an index or roadmaps is a legacy home, and its
    # global store is left for the import.
    class Bootstrap
      LEGACY = %w[store projects INDEX.md roadmaps].freeze
      AGENT_INSTRUCTIONS = <<~MD
        # Plastic: Agent Instructions

        Read `PLASTIC.md` in this directory for the core conventions; deeper doctrine lives
        in the chapters `plastic help TOPIC` prints. Follow it exactly. Never modify it:
        it is overwritten on plugin updates.

        This file (`AGENTS.md`) is where project-specific rules live.

        ---
      MD

      def initialize(home)
        @home = home
      end

      def call
        puts "  First install - bootstrapping store..."
        legacy = LEGACY.any? { |entry| File.exist?(File.join(@home, entry)) }
        FileUtils.mkdir_p(StoreLayout.global_store(@home))
        write_files
        Graph.create(home: @home, store: StoreLayout::GLOBAL) unless legacy
        puts "  Store bootstrapped"
      end

      private

      def write_files
        Files.write_if_missing(File.join(@home, "config.yml"), "version: 3\n")
        Files.write_if_missing(File.join(@home, "projects.yml"), "---\nprojects: {}\n")
        Files.write_if_missing(File.join(@home, "AGENTS.md"), AGENT_INSTRUCTIONS)
      end
    end
  end
end
