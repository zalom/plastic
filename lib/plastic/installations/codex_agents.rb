# frozen_string_literal: true

require "fileutils"
require_relative "codex_toml"
require_relative "files"

module Plastic
  module Installations
    # Writes the Codex agents folder: one Plastic-owned TOML document for each
    # role file of a package. Codex reads standalone TOML agents, never the
    # markdown copy, so this is a render, not a copy.
    class CodexAgents
      def initialize(package_root, models: {}, efforts: {}, skip: [], workers: nil)
        @package_root = package_root
        @workers = workers
        @picks = { model: models, effort: efforts }
        @skip = skip
      end

      def call(root) = sources.filter_map { |source| write(root, source) }

      private

      def sources = Dir.glob(File.join(@package_root, "agents", "*.md"))

      def write(root, source)
        FileUtils.mkdir_p(root)
        name = File.basename(source, ".md")
        CodexToml.write(root, source, @picks[:model][name], @picks[:effort][name], @workers) unless @skip.include?(name)
      end
    end
  end
end
