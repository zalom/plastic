# frozen_string_literal: true

require "json"
require_relative "../../../invalid"

module Plastic
  module Graph
    module Work
      module Completion
        # Reads criterion evidence only from a file inside the selected intent.
        class Evidence
          def self.read(folder, intent, path, criteria)
            full = scoped_path(folder, intent, path)
            validate(JSON.parse(File.read(full, encoding: "UTF-8")), criteria)
          rescue SystemCallError, JSON::ParserError => error
            raise Invalid, "cannot read criterion evidence: #{error.message.lines.first.strip}"
          end

          def self.scoped_path(folder, intent, path)
            root = File.realpath(folder.path(intent.dir))
            candidate = File.expand_path(path, root)
            raise Invalid, "evidence must be a file inside intent #{intent.intent_id}" unless candidate.start_with?("#{root}/")

            full = File.realpath(candidate)
            raise Invalid, "evidence must stay inside intent #{intent.intent_id}" unless full.start_with?("#{root}/")

            full
          end

          def self.validate(evidence, keys)
            raise Invalid, "evidence must be a JSON object from criterion key to evidence text" unless evidence.is_a?(Hash)

            problems = key_problems(evidence, keys)
            raise Invalid, "evidence must map every criterion key to nonempty evidence text; #{problems.join("; ")}" if problems.any?

            evidence
          end

          def self.key_problems(evidence, keys)
            found = { "missing keys" => keys - evidence.keys, "extra keys" => evidence.keys - keys, "blank keys" => blank_keys(evidence, keys) }
            found.reject { |_label, names| names.empty? }.map { |label, names| "#{label}: #{names.join(", ")}" }
          end

          def self.blank_keys(evidence, keys)
            evidence.select { |key, value| keys.include?(key) && !(value.is_a?(String) && !value.strip.empty?) }.keys
          end
        end
      end
    end
  end
end
