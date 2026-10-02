# frozen_string_literal: true

require_relative "../cli/command"
require "fileutils"
require "json"
require "tempfile"

module Plastic
  module Commands
    # Builds the retrieval handoff manifest; the harness chooses its evidence.
    class IntentDiscover < CLI::Command
      argument :intent_id, label: "ID", text: "the owning intent"
      argument :terms, label: "TERMS", text: "literal search terms", rest: true
      reads :knowledge
      writes :knowledge

      def call
        output.row("discovery", persist(manifest))
        output.next_step("none", because: "the retrieval candidates were recorded")
      end

      private

      def manifest
        { intent_id: parsed.fetch(:intent_id), query: parsed.fetch(:terms), scope: [scope.slug], candidates: [] }
      end

      def persist(document)
        FileUtils.mkdir_p(File.dirname(manifest_path))
        Tempfile.create(["discovery", ".json"], File.dirname(manifest_path)) do |file|
          file.write(JSON.pretty_generate(document))
          file.flush
          File.rename(file.path, manifest_path)
        end
        document
      end

      def manifest_path = File.join(scope.root, "discovery", "#{parsed.fetch(:intent_id)}.json")
    end
  end
end
