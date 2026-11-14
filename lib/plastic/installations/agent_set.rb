# frozen_string_literal: true

require_relative "agent_record"

module Plastic
  module Installations
    # The agents Plastic installs for, each a hash of key, name, folder and,
    # for Codex, its own home folder.
    class AgentSet
      DEFAULTS = [
        { key: "claude", name: "Claude Code", dir: File.join(Dir.home, ".claude"), skill_prefix: "/" },
        { key: "codex", name: "Codex CLI", dir: File.join(Dir.home, ".agents"), home_dir: File.join(Dir.home, ".codex"), skill_prefix: "$" },
        { key: "hermes", name: "Hermes", dir: File.join(Dir.home, ".hermes") }
      ].freeze

      attr_reader :agents

      def initialize(agents = DEFAULTS)
        @agents = agents
      end

      def config(key) = agents.find { |agent| agent[:key] == key }

      def keys = agents.map { |agent| agent[:key] }

      def record(key) = (found = config(key)) && AgentRecord.new(found)

      def installed_keys = keys.select { |key| record(key).installed? }

      def registered?(key) = !!record(key)&.registered?
    end
  end
end
