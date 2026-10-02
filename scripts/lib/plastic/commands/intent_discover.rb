# frozen_string_literal: true

require_relative "../routine"
require "digest"

module Plastic
  module Commands
    # Builds the retrieval handoff manifest; the harness chooses its evidence.
    class IntentDiscover < Routine
      subject :intent_id
      argument :intent_id, label: "ID", text: "the owning intent"
      argument :terms, label: "TERMS", text: "literal search terms", rest: true
      option :source_projects, switch: "--source-project SLUG", text: "a source store", repeatable: true
      reads :knowledge
      writes :knowledge

      workflow :code_discover_retrieval, next: :agent_external_agent_workflow
      workflow :agent_external_agent_workflow, next: :noop

      class << self
        def declared_facts = super + %i[scope_slug plastic_home store_root]
      end

      def call
        validate_intent_id!
        super
      end

      private

      def subject
        Digest::SHA256.hexdigest([parsed.fetch(:intent_id), parsed.fetch(:terms), source_key].join("\0"))
      end

      def source_key
        sources = parsed.fetch(:source_projects).map(&:strip).reject(&:empty?).uniq.sort
        (sources.empty? ? [scope.slug] : sources).join(",")
      end

      def context(routine_run)
        Context.new(declared: self.class.declared_facts, facts: routine_run.facts.merge(parsed).merge(scope_facts), graphs:, session:)
      end

      def scope_facts = { scope_slug: scope.slug, plastic_home: scope.plastic_home, store_root: scope.root }

      def validate_intent_id!
        id = parsed.fetch(:intent_id)
        raise CLI::Command::Usage, "invalid intent id #{id.inspect}" unless /\A\d+[a-z0-9]*\z/.match?(id)
      end

      def report(value, ctx)
        output.row("discovery", ctx.discovery) if ctx.discovery
        super
      end
    end
  end
end
