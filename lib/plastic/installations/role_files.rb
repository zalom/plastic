# frozen_string_literal: true

require "fileutils"
require_relative "role_text"

module Plastic
  module Installations
    # Copies the agents/NAME.md role files of a package into one agents folder.
    # A model or effort the person set for a role rewrites that line of the
    # frontmatter. A declined advisor leaves out the consultation roles.
    class RoleFiles
      def self.set_line(text, key, value)
        return text.sub(/^#{key}:[^\n]*$/) { "#{key}: #{value}" } if text.match?(/^#{key}:/)

        text.sub(/^(model:[^\n]*)$/) { "#{Regexp.last_match(1)}\n#{key}: #{value}" }
      end

      def initialize(package_root, models: {}, efforts: {}, skip: [], workers: nil)
        @package_root = package_root
        @workers = workers
        @picks = { "model" => models, "effort" => efforts }
        @skip = skip
      end

      def call(root) = sources.map { |source| copy(source, root) }

      private

      def sources = Dir.glob(File.join(@package_root, "agents", "*.md")).reject { |source| @skip.include?(File.basename(source, ".md")) }

      def copy(source, root)
        FileUtils.mkdir_p(root)
        target = File.join(root, File.basename(source))
        File.write(target, rewritten(RoleText.fill(File.read(source), @workers), File.basename(source, ".md")))
        target
      end

      def rewritten(text, name)
        @picks.transform_values { |picked| picked[name] }.compact.reduce(text) { |kept, (key, value)| RoleFiles.set_line(kept, key, value) }
      end
    end
  end
end
