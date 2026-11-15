# frozen_string_literal: true

require "yaml"

module Plastic
  module Installations
    # Renames the retired advisor names in a config without discarding a
    # current key. A section that is not the expected shape is left alone.
    module AdvisorMigration
      RENAMES = {
        "plastic-advisor" => "plastic-primary-advisor",
        "plastic-faux-advisor" => "plastic-secondary-advisor"
      }.freeze

      module_function

      def call(config)
        return {} unless config.is_a?(Hash)

        copy = Marshal.load(Marshal.dump(config))
        rename_default(copy)
        rename_sections(copy)
        copy
      end

      # True when the file held a retired name and was rewritten.
      def file(path)
        return false unless path && File.file?(path)

        parsed = YAML.safe_load_file(path)
        migrated = call(parsed)
        return false if !parsed.is_a?(Hash) || migrated == parsed

        File.write(path, YAML.dump(migrated))
        true
      rescue Psych::Exception
        false
      end

      def rename_default(config)
        claude = config["advisor"].is_a?(Hash) ? config["advisor"]["claude"] : nil
        claude["default"] = RENAMES.fetch(claude["default"]) if claude.is_a?(Hash) && RENAMES.key?(claude["default"])
      end

      def rename_sections(config)
        agents = config["agents"]
        return unless agents.is_a?(Hash)

        %w[models efforts].filter_map { |part| agents[part] }.grep(Hash).each do |section|
          [section, *%w[claude codex].map { |harness| section[harness] }].grep(Hash).each { |keys| rename_keys(keys) }
        end
      end

      def rename_keys(section)
        RENAMES.each do |retired, current|
          section[current] = section[retired] if !section.key?(current) && section.key?(retired)
          section.delete(retired)
        end
      end
    end
  end
end
