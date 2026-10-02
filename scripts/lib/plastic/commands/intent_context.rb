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
      rescue Graph::RetrievalGraph::MaintenanceRequired, Graph::RetrievalGraph::MissingReference, KeyError => error
        raise CLI::Command::Failure, error.message
      end

      private

      def validate_intent!
        id = parsed.fetch(:intent_id)
        raise CLI::Command::Usage, "invalid intent id #{id.inspect}" unless /\A\d+[a-z0-9]*\z/.match?(id)
        raise CLI::Command::Failure, "no intent #{id} in owning store" unless Graph.open(home: scope.plastic_home, store: scope.slug).retrieval.intent(id)
      end

      def readback
        document = stored_context
        document.merge("freshness" => freshness(document))
      rescue Errno::ENOENT
        raise CLI::Command::Failure, "no retrieval context for intent #{parsed.fetch(:intent_id)}"
      end

      def validated_submission
        submission = JSON.parse(File.read(parsed.fetch(:from)))
        raise CLI::Command::Usage, "context submission must be a JSON object" unless submission.is_a?(Hash)

        required_fields(submission)
        evidence = submission.fetch("evidence")
        validate_evidence(evidence)
        selected = evidence.uniq
        submission.merge(submission_metadata(selected))
      end

      def required_fields(submission)
        %w[evidence facts interpretations gaps rulings architecture].each { |field| submission.fetch(field) }
        validate_context_categories(submission)
        validate_architecture(submission.fetch("architecture"))
      end

      def submission_metadata(selected)
        { "intent_id" => parsed.fetch(:intent_id), "evidence" => selected,
          "archive_states" => selected.to_h { |reference| [reference, archived?(reference)] },
          "discovery" => discovery.slice("query", "scope") }
      end

      def validate_context_categories(submission)
        fields = %w[evidence facts interpretations gaps rulings]
        return if fields.all? { |field| submission.fetch(field).is_a?(Array) }

        raise CLI::Command::Usage, "evidence, facts, interpretations, gaps, and rulings must be arrays"
      end

      def validate_architecture(architecture)
        raise CLI::Command::Usage, "architecture must be an object" unless architecture.is_a?(Hash)

        %w[provider revision coverage limitations].each { |field| architecture.fetch(field) }
        validate_architecture_identity(architecture)
        raise CLI::Command::Usage, "architecture coverage and limitations must be arrays" unless %w[coverage limitations].all? { |field| architecture.fetch(field).is_a?(Array) }
        return unless architecture.key?("receipt") && !architecture.fetch("receipt").is_a?(Hash)

        raise CLI::Command::Usage, "architecture receipt must be an object"
      end

      def validate_architecture_identity(architecture)
        provider = architecture.fetch("provider")
        revision = architecture.fetch("revision")
        raise CLI::Command::Usage, "architecture provider must be a safe identifier" unless /\A[a-z0-9][a-z0-9_-]*\z/.match?(provider.to_s)
        raise CLI::Command::Usage, "architecture revision must be a string" unless revision.is_a?(String)
      end

      def validate_evidence(evidence)
        allowed = discovery.fetch("candidates").map { |candidate| candidate.fetch("uri") }
        evidence.each do |reference|
          raise CLI::Command::Failure, "evidence was not discovered: #{reference}" unless allowed.include?(reference)

          fields = source_retrieval(reference).fetch_reference(reference)
          raise CLI::Command::Failure, "evidence revision changed: #{reference}" unless fields.fetch(:uri) == reference
        end
      end

      def discovery
        row = graphs.databases.fetch(:knowledge).row("SELECT data FROM retrieval_discoveries WHERE intent_id = :intent_id AND origin_id = :origin",
          intent_id: parsed.fetch(:intent_id), origin: graphs.retrieval.origin_id)
        return JSON.parse(row.fetch("data")) if row

        JSON.parse(File.read(discovery_path))
      end

      def source(reference) = reference[/\Aplastic:\/\/([^\/]+)/, 1]

      def freshness(document)
        { "evidence" => document.fetch("evidence").map { |reference| evidence_state(document, reference) },
          "architecture" => architecture_state(document.fetch("architecture")) }
      end

      def evidence_state(document, reference)
        retrieval = source_retrieval(reference)
        retrieval.fetch_reference(reference)
        current = retrieval.fetch_reference(strip_revision(reference))
        archived = retrieval.archived?(current.fetch(:intent_id))
        state = current.fetch(:uri) == reference && document.fetch("archive_states", {}).fetch(reference, archived) == archived ? "fresh" : "stale"
        { "uri" => reference, "state" => state, "archived" => archived }
      rescue Graph::RetrievalGraph::MissingReference
        evidence_missing_or_stale(reference)
      end

      def evidence_missing_or_stale(reference)
        retrieval = source_retrieval(reference)
        retrieval.fetch_reference(reference)
        { "uri" => reference, "state" => "stale" }
      rescue Graph::RetrievalGraph::MissingReference
        { "uri" => reference, "state" => "missing" }
      end

      def archived?(reference)
        retrieval = source_retrieval(reference)
        fields = retrieval.fetch_reference(reference)
        retrieval.archived?(fields.fetch(:intent_id))
      end

      def architecture_state(architecture)
        receipt = stored_architecture_receipt(architecture.fetch("provider"))
        return architecture_status(architecture, "missing") unless receipt.fetch("available", true)

        architecture_status(architecture, receipt.fetch("revision") == architecture.fetch("revision") ? "fresh" : "stale")
      rescue Errno::ENOENT, JSON::ParserError, KeyError
        architecture_status(architecture, "missing")
      end

      def architecture_status(architecture, state)
        { "provider" => architecture.fetch("provider"), "revision" => architecture.fetch("revision"), "state" => state }
      end

      def stored_architecture_receipt(provider)
        row = graphs.databases.fetch(:knowledge).row("SELECT data FROM architecture_receipts WHERE provider = :provider AND origin_id = :origin",
          provider:, origin: graphs.retrieval.origin_id)
        return JSON.parse(row.fetch("data")) if row

        JSON.parse(File.read(architecture_receipt_path(provider)))
      end

      def strip_revision(reference) = reference.sub(/\?revision=[0-9a-f]{64}\z/, "")

      def source_retrieval(reference)
        slug = source(reference)
        store = File.join(scope.plastic_home, "stores", slug)
        missing = Graph::Schema::STORE.map { |key| Graph::Schema.file(key) }.reject { |file| File.file?(File.join(store, file)) }
        raise Graph::RetrievalGraph::MaintenanceRequired, "retrieval maintenance is required before source #{slug} can be read" if missing.any?

        knowledge = File.join(store, "knowledge_graph.db")
        complete = Graph::ReferenceBackfill.complete?(knowledge, Graph::Origin.new(scope.plastic_home).id)
        raise Graph::RetrievalGraph::MaintenanceRequired, "retrieval maintenance is required before source #{slug} can be read" unless complete

        Graph.open(home: scope.plastic_home, store: slug).retrieval
      end

      def context_path = File.join(scope.root, "context", "#{parsed.fetch(:intent_id)}.json")

      def stored_context
        row = graphs.databases.fetch(:knowledge).row("SELECT data FROM retrieval_contexts WHERE intent_id = :intent_id AND origin_id = :origin",
          intent_id: parsed.fetch(:intent_id), origin: graphs.retrieval.origin_id)
        return JSON.parse(row.fetch("data")) if row

        JSON.parse(File.read(context_path))
      end

      def discovery_path = File.join(scope.root, "discovery", "#{parsed.fetch(:intent_id)}.json")

      def persist(document)
        body = JSON.pretty_generate(document)
        architecture = document.fetch("architecture")
        receipt = architecture["receipt"]
        graphs.databases.fetch(:knowledge).transaction do |batch|
          batch.put(:retrieval_contexts, { intent_id: parsed.fetch(:intent_id), data: body, updated_at: Plastic.now })
          batch.put(:architecture_receipts, { provider: architecture.fetch("provider"), data: JSON.pretty_generate(receipt), updated_at: Plastic.now }) if receipt
        end
        persist_architecture_receipt(architecture) if receipt
        FileUtils.mkdir_p(File.dirname(context_path))
        Tempfile.create(["context", ".json"], File.dirname(context_path)) do |file|
          file.write(body)
          file.flush
          File.rename(file.path, context_path)
        end
        document
      end

      def persist_architecture_receipt(architecture)
        path = architecture_receipt_path(architecture.fetch("provider"))
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, JSON.pretty_generate(architecture.fetch("receipt")))
      end

      def architecture_receipt_path(provider) = File.join(scope.root, "architecture", "#{provider}.json")
    end
  end
end
