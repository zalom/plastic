# frozen_string_literal: true

module Plastic
  module Commands
    # Validates the agent-selected context before the owning store writes it.
    class ContextSubmission
      REQUIRED_FIELDS = %w[evidence facts interpretations gaps rulings architecture].freeze
      CATEGORY_FIELDS = %w[evidence facts interpretations gaps rulings].freeze

      def initialize(intent_id:, discovery:, source:)
        @intent_id = intent_id
        @discovery = discovery
        @source = source
      end

      def validate(path)
        submission = JSON.parse(File.read(path))
        raise CLI::Command::Usage, "context submission must be a JSON object" unless submission.is_a?(Hash)

        required_fields!(submission)
        selected = selected_evidence(submission)
        submission.merge(metadata(selected))
      end

      private

      attr_reader :intent_id, :discovery, :source

      def required_fields!(submission)
        REQUIRED_FIELDS.each { |field| submission.fetch(field) }
        validate_categories!(submission)
        validate_architecture!(submission.fetch("architecture"))
      end

      def validate_categories!(submission)
        return if CATEGORY_FIELDS.all? { |field| submission.fetch(field).is_a?(Array) }

        raise CLI::Command::Usage, "evidence, facts, interpretations, gaps, and rulings must be arrays"
      end

      def validate_architecture!(architecture)
        raise CLI::Command::Usage, "architecture must be an object" unless architecture.is_a?(Hash)

        %w[provider revision coverage limitations].each { |field| architecture.fetch(field) }
        validate_identity!(architecture)
        valid_lists = %w[coverage limitations].all? { |field| architecture.fetch(field).is_a?(Array) }
        raise CLI::Command::Usage, "architecture coverage and limitations must be arrays" unless valid_lists
        return unless architecture.key?("receipt") && !architecture.fetch("receipt").is_a?(Hash)

        raise CLI::Command::Usage, "architecture receipt must be an object"
      end

      def validate_identity!(architecture)
        provider = architecture.fetch("provider")
        revision = architecture.fetch("revision")
        valid_provider = /\A[a-z0-9][a-z0-9_-]*\z/.match?(provider.to_s)
        raise CLI::Command::Usage, "architecture provider must be a safe identifier" unless valid_provider
        raise CLI::Command::Usage, "architecture revision must be a string" unless revision.is_a?(String)
      end

      def selected_evidence(submission)
        evidence = submission.fetch("evidence")
        allowed = discovery.fetch("candidates").map { |candidate| candidate.fetch("uri") }
        evidence.each { |reference| validate_evidence!(reference, allowed) }
        evidence.uniq
      end

      def validate_evidence!(reference, allowed)
        raise CLI::Command::Failure, "evidence was not discovered: #{reference}" unless allowed.include?(reference)

        fields = source.retrieval(reference).fetch_reference(reference)
        raise CLI::Command::Failure, "evidence revision changed: #{reference}" unless fields.fetch(:uri) == reference
      end

      def metadata(selected)
        { "intent_id" => intent_id, "evidence" => selected,
          "archive_states" => selected.to_h { |reference| [reference, archived?(reference)] },
          "discovery" => discovery.slice("query", "scope") }
      end

      def archived?(reference)
        retrieval = source.retrieval(reference)
        fields = retrieval.fetch_reference(reference)
        retrieval.archived?(fields.fetch(:intent_id))
      end
    end
  end
end
