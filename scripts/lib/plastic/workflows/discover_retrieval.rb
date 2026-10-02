# frozen_string_literal: true

require "fileutils"
require "json"
require "tempfile"
require_relative "../code_workflow"
require_relative "../external_agent_workflow"

module Plastic
  module Workflows
    # Records lexical retrieval candidates before an external agent selects them.
    class DiscoverRetrieval < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :intent, :source_scope, :discovery, :handoff_text, :context_command, :context_complete

      read "find the owning intent" do |context|
        context[:intent] = context.retrieval.intent(context.intent_id)
      end

      read "find the saved retrieval context" do |context|
        row = context.database(:knowledge).row("SELECT data FROM retrieval_contexts WHERE intent_id = :intent_id AND origin_id = :origin",
          intent_id: context.intent_id, origin: context.retrieval.origin_id)
        context[:context_complete] = context_matches?(row, context)
      end

      gate "no intent %{intent_id} in owning store", stops: :failure, pass: ->(context) { !context.intent.nil? }

      step "record retrieval discovery", done: ->(context) { !context.discovery.nil? } do |context|
        source_scope = sources(context)
        document = manifest(context, source_scope)
        persist(context, document)
        context[:source_scope] = source_scope
        context[:discovery] = document
        context[:handoff_text] = "Submit the selected retrieval context with plastic intent context #{context.intent_id} --from FILE --project #{context.scope_slug}."
        context[:context_command] = document.fetch(:workflow).fetch("context")
      end

      outcome :done, offers: nil, because: "retrieval discovery is recorded"

      class << self
        private

        def sources(context)
          values = context.source_projects
          values = ENV.fetch("PLASTIC_SOURCE_PROJECTS", "").split(",") if values.empty?
          list = canonical_sources(values)
          list = [context.scope_slug] if list.empty?
          validate_sources(context, list)
          list
        end

        def canonical_sources(values) = values.map(&:strip).reject(&:empty?).uniq.sort

        def validate_sources(context, list)
          known = Dir.glob(File.join(context.plastic_home, "stores", "*")).filter_map do |path|
            File.basename(path) if File.directory?(path)
          end
          unknown = list - (known | ["global"])
          raise CLI::Command::Failure, "unknown source projects: #{unknown.join(", ")}" if unknown.any?
        end

        def manifest(context, source_scope)
          { intent_id: context.intent_id, query: context.terms, scope: source_scope, candidates: candidates(context, source_scope),
            workflow: ExternalAgentWorkflow.retrieval_handoff(intent_id: context.intent_id, terms: context.terms, sources: source_scope, project: context.scope_slug) }
        end

        def candidates(context, source_scope)
          source_scope.flat_map { |slug| rows(context, slug) }.sort_by { |row| [-row.fetch("rrf_score"), row.fetch("uri")] }
        end

        def rows(context, slug)
          retrieval = maintained_retrieval(context, slug)
          retrieval.search(context.terms, migrate: false).each_with_index.map do |row, index|
            reference = retrieval.search_reference(row)
            row.merge(reference.transform_keys(&:to_s)).merge("store" => slug, "local_rank" => index + 1,
              "rrf_score" => 1.0 / (61 + index), "archived" => retrieval.archived?(row.fetch("intent_id")))
          end
        end

        def maintained_retrieval(context, slug)
          missing = Graph::Schema::STORE.map { |key| Graph::Schema.file(key) }.reject do |file|
            File.file?(File.join(context.plastic_home, "stores", slug, file))
          end
          raise Graph::RetrievalGraph::MaintenanceRequired, "retrieval maintenance is required before source #{slug} can be read" if missing.any?

          Graph.open(home: context.plastic_home, store: slug).retrieval
        end

        def persist(context, document)
          body = JSON.pretty_generate(document)
          persist_row(context, body)
          persist_file(context, body)
        end

        def persist_row(context, body)
          context.database(:knowledge).transaction do |batch|
            batch.put(:retrieval_discoveries, { intent_id: context.intent_id, data: body, updated_at: Plastic.now })
          end
        end

        def persist_file(context, body)
          path = File.join(context.store_root, "discovery", "#{context.intent_id}.json")
          FileUtils.mkdir_p(File.dirname(path))
          Tempfile.create(["discovery", ".json"], File.dirname(path)) do |file|
            file.write(body)
            file.flush
            File.rename(file.path, path)
          end
        end

        def context_matches?(row, context)
          return false unless row

          saved = JSON.parse(row.fetch("data")).fetch("discovery")
          saved.fetch("query") == context.terms && saved.fetch("scope") == sources(context)
        rescue JSON::ParserError, KeyError
          false
        end
      end
    end
  end
end
