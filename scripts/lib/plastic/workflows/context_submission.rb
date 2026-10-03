# frozen_string_literal: true

require "json"
require_relative "../cli/command/failure"
require_relative "../cli/command/usage"

module Plastic
  module Workflows
    # Validates the agent-selected context before the owning store writes it.
    class ContextSubmission
      CATEGORY_FIELDS = %w[evidence facts interpretations gaps rulings].freeze

      def initialize(intent_id:, discovery:, source:)
        @intent_id = intent_id
        @discovery = discovery
        @source = source
      end

      def validate(path)
        submission = JSON.parse(File.read(path))
        raise CLI::Command::Usage, "context submission must be a JSON object" unless submission.is_a?(Hash)

        require_fields(submission)
        selected = selected_evidence(submission)
        submission.slice(*CATEGORY_FIELDS).merge(metadata(selected))
      end

      private

      attr_reader :intent_id, :discovery, :source

      def require_fields(submission)
        CATEGORY_FIELDS.each { |field| submission.fetch(field) }
        validate_categories(submission)
      end

      def validate_categories(submission)
        return if CATEGORY_FIELDS.all? { |field| submission.fetch(field).is_a?(Array) }

        raise CLI::Command::Usage, "evidence, facts, interpretations, gaps, and rulings must be arrays"
      end

      def selected_evidence(submission)
        evidence = submission.fetch("evidence")
        evidence.each { |reference| validate_evidence(reference, discovered_uris) }
        evidence.uniq
      end

      def discovered_uris = discovery.fetch("candidates").map { |candidate| candidate.fetch("uri") }

      def validate_evidence(reference, allowed)
        raise CLI::Command::Failure, "evidence was not discovered: #{reference}" unless allowed.include?(reference)

        fields = source.retrieval(reference).fetch_reference(reference)
        raise CLI::Command::Failure, "evidence revision changed: #{reference}" unless fields.fetch(:uri) == reference
      end

      def metadata(selected)
        { "intent_id" => intent_id, "evidence" => selected,
          "archive_states" => selected.to_h { |reference| [reference, source.retrieval(reference).archived_reference?(reference)] },
          "discovery" => discovery.slice("query", "scope") }
      end
    end
  end
end
