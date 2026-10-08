# frozen_string_literal: true

require "json"
require_relative "../../../invalid"

module Plastic
  module Graph
    module Work
      module Completion
        # Reads criterion evidence only from a file inside the selected intent.
        class Evidence
          def initialize(folder, intent)
            @folder = folder
            @dir = intent.dir
            @intent_id = intent.intent_id
          end

          def read(path, keys)
            Evidence.validate(JSON.parse(File.read(scoped_path(path), encoding: "UTF-8")), keys)
          rescue SystemCallError, JSON::ParserError => error
            raise Invalid, "cannot read criterion evidence: #{error.message.lines.first.strip}"
          end

          def self.validate(evidence, keys)
            raise Invalid, "evidence must be a JSON object from criterion key to evidence text" unless evidence.is_a?(Hash)

            problems = key_problems(evidence, keys)
            raise Invalid, "evidence must map every criterion key to nonempty evidence text; #{problems.join("; ")}" if problems.any?

            evidence
          end

          def self.key_problems(evidence, keys)
            given = evidence.keys
            found = { "missing keys" => keys - given, "extra keys" => given - keys, "blank keys" => blank_keys(evidence, keys) }
            found.reject { |_label, names| names.empty? }.map { |label, names| "#{label}: #{names.join(", ")}" }
          end

          def self.blank_keys(evidence, keys)
            evidence.select { |key, value| keys.include?(key) && !(value.is_a?(String) && !value.strip.empty?) }.keys
          end

          private

          def scoped_path(path)
            candidate = File.expand_path(path, root)
            raise Invalid, "evidence must be a file inside intent #{@intent_id}" unless inside?(candidate)

            full = File.realpath(candidate)
            raise Invalid, "evidence must stay inside intent #{@intent_id}" unless inside?(full)

            full
          end

          def root = @root ||= File.realpath(@folder.path(@dir))

          def inside?(path) = path.start_with?("#{root}/")
        end
      end
    end
  end
end
