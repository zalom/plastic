# frozen_string_literal: true

require "fileutils"
require_relative "codex_toml"
require_relative "files"
require_relative "../config/agent_models"

module Plastic
  module Installations
    # Writes the Codex agents folder: one Plastic-owned TOML document for each
    # role file of a package. Codex reads standalone TOML agents, never the
    # markdown copy, so this is a render, not a copy.
    class CodexAgents
      def initialize(package_root)
        @package_root = package_root
      end

      def call(root, models: {}, efforts: {}, advisor: true)
        sources = Dir.glob(File.join(@package_root, "agents", "*.md"))
        return [] if sources.empty?

        FileUtils.mkdir_p(root)
        sources.filter_map do |source|
          name = File.basename(source, ".md")
          write(root, source, models[name], efforts[name]) if advisor || !Config::AgentModels::CONSULTATION_AGENTS.include?(name)
        end
      end

      private

      def write(root, source, model, effort)
        target = File.join(root, "#{File.basename(source, ".md")}.toml")
        Files.write_text(target, CodexToml.render(source, model, effort))
        target
      end
    end
  end
end
