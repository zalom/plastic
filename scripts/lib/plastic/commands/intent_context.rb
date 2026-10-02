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
        validate_intent!
        output.row("context", parsed[:from] ? persist(validated_submission) : readback)
        output.next_step("none", because: "the retrieval context was read")
      rescue Errno::ENOENT, JSON::ParserError => error
        raise CLI::Command::Usage, error.message
      rescue Graph::RetrievalGraph::MissingReference, KeyError => error
        raise CLI::Command::Failure, error.message
      end

      private

      def validate_intent!
        id = parsed.fetch(:intent_id)
        raise CLI::Command::Usage, "invalid intent id #{id.inspect}" unless /\A\d+[a-z0-9]*\z/.match?(id)
        raise CLI::Command::Failure, "no intent #{id} in owning store" unless Graph.open(home: scope.plastic_home, store: scope.slug).retrieval.intent(id)
      end

      def readback
        document = JSON.parse(File.read(context_path))
        document.merge("freshness" => freshness(document))
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
        %w[evidence facts interpretations gaps rulings architecture].each { |field| submission.fetch(field) }
        validate_context_categories(submission)
        validate_architecture(submission.fetch("architecture"))
      end

      def validate_context_categories(submission)
        fields = %w[evidence facts interpretations gaps rulings]
        return if fields.all? { |field| submission.fetch(field).is_a?(Array) }

        raise CLI::Command::Usage, "evidence, facts, interpretations, gaps, and rulings must be arrays"
      end

      def validate_architecture(architecture)
        raise CLI::Command::Usage, "architecture must be an object" unless architecture.is_a?(Hash)

        %w[provider revision coverage limitations].each { |field| architecture.fetch(field) }
        return if %w[coverage limitations].all? { |field| architecture.fetch(field).is_a?(Array) }

        raise CLI::Command::Usage, "architecture coverage and limitations must be arrays"
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

      def freshness(document)
        { "evidence" => document.fetch("evidence").map { |reference| evidence_state(reference) } }
      end

      def evidence_state(reference)
        retrieval = Graph.open(home: scope.plastic_home, store: source(reference)).retrieval
        retrieval.fetch_reference(reference)
        current = retrieval.fetch_reference(strip_revision(reference))
        { "uri" => reference, "state" => ((current.fetch(:uri) == reference) ? "fresh" : "stale") }
      rescue Graph::RetrievalGraph::MissingReference
        { "uri" => reference, "state" => "missing" }
      end

      def strip_revision(reference) = reference.sub(/\?revision=[0-9a-f]{64}\z/, "")

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
