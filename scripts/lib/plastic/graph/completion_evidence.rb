# frozen_string_literal: true

require "json"
require_relative "../invalid"

module Plastic
  module Graph
    # Reads criterion evidence only from a file inside the selected intent.
    class CompletionEvidence
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

      def self.validate(evidence, criteria)
        valid = evidence.is_a?(Hash) && evidence.keys.sort == criteria.uniq.sort &&
          evidence.values.all? { |value| value.is_a?(String) && !value.strip.empty? }
        raise Invalid, "evidence must map every exact done criterion to nonempty evidence text" unless valid

        evidence
      end
    end
  end
end
