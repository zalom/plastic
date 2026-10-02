# frozen_string_literal: true

require_relative "../cli/command"
require "fileutils"
require "json"
require "tempfile"

module Plastic
  module Commands
    # Persists the agent's selected evidence without judging its relevance.
    class IntentContext < CLI::Command
      argument :intent_id, label: "ID", text: "the owning intent"
      option :from, switch: "--from FILE", text: "JSON evidence selection and architecture context"
      reads :knowledge
      writes :knowledge

      def call
        output.row("context", parsed[:from] ? persist(validated_submission) : readback)
        output.next_step("none", because: "the retrieval context was read")
      rescue Errno::ENOENT, JSON::ParserError => error
        raise CLI::Command::Usage, error.message
      rescue Graph::RetrievalGraph::MissingReference, KeyError => error
        raise CLI::Command::Failure, error.message
      end

      private

      def readback
        JSON.parse(File.read(context_path))
      rescue Errno::ENOENT
        raise CLI::Command::Failure, "no retrieval context for intent #{parsed.fetch(:intent_id)}"
      end

      def validated_submission
        submission = JSON.parse(File.read(parsed.fetch(:from)))
        required_fields(submission)
        evidence = submission.fetch("evidence")
        validate_evidence(evidence)
        submission.merge("intent_id" => parsed.fetch(:intent_id), "evidence" => evidence.uniq)
      end

      def required_fields(submission)
        %w[evidence facts judgments architecture].each { |field| submission.fetch(field) }
        raise CLI::Command::Usage, "evidence, facts, and judgments must be arrays" unless %w[evidence facts judgments].all? { |field| submission.fetch(field).is_a?(Array) }
      end

      def validate_evidence(evidence)
        allowed = discovery.fetch("candidates").map { |candidate| candidate.fetch("uri") }
        evidence.each do |reference|
          raise CLI::Command::Failure, "evidence was not discovered: #{reference}" unless allowed.include?(reference)

          fields = Graph.open(home: scope.plastic_home, store: source(reference)).retrieval.fetch_reference(reference)
          raise CLI::Command::Failure, "evidence revision changed: #{reference}" unless fields.fetch(:uri) == reference
        end
      end

      def discovery = JSON.parse(File.read(discovery_path))

      def source(reference) = reference[/\Aplastic:\/\/([^\/]+)/, 1]

      def context_path = File.join(scope.root, "context", "#{parsed.fetch(:intent_id)}.json")

      def discovery_path = File.join(scope.root, "discovery", "#{parsed.fetch(:intent_id)}.json")

      def persist(document)
        FileUtils.mkdir_p(File.dirname(context_path))
        Tempfile.create(["context", ".json"], File.dirname(context_path)) do |file|
          file.write(JSON.pretty_generate(document))
          file.flush
          File.rename(file.path, context_path)
        end
        document
      end
    end
  end
end
