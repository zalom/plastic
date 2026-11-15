# frozen_string_literal: true

require "fileutils"
require_relative "../config/agent_models"

module Plastic
  module Installations
    # Copies the agents/NAME.md role files of a package into one agents folder.
    # A model or effort the person set for a role rewrites that line of the
    # frontmatter. A declined advisor leaves out the consultation roles.
    class RoleFiles
      def initialize(package_root)
        @package_root = package_root
      end

      def call(root, models: {}, efforts: {}, advisor: true)
        sources = Dir.glob(File.join(@package_root, "agents", "*.md"))
        sources = sources.reject { |source| consultation?(source) } unless advisor
        return [] if sources.empty?

        FileUtils.mkdir_p(root)
        sources.map { |source| copy(source, File.join(root, File.basename(source)), models, efforts) }
      end

      private

      def consultation?(source) = Config::AgentModels::CONSULTATION_AGENTS.include?(File.basename(source, ".md"))

      def copy(source, target, models, efforts)
        name = File.basename(source, ".md")
        File.write(target, rewritten(File.read(source), models[name], efforts[name]))
        target
      end

      def rewritten(text, model, effort)
        text = text.sub(/^model:[^\n]*$/) { "model: #{model}" } if model
        effort ? with_effort(text, effort) : text
      end

      def with_effort(text, effort)
        return text.sub(/^effort:[^\n]*$/) { "effort: #{effort}" } if text.match?(/^effort:/)

        text.sub(/^(model:[^\n]*)$/) { "#{Regexp.last_match(1)}\neffort: #{effort}" }
      end
    end
  end
end
