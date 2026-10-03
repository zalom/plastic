# frozen_string_literal: true

require "fileutils"
require "json"
require "tempfile"

module Plastic
  module Workflows
    # Writes a discovery manifest to the owning graph and its durable file.
    class DiscoveryPersistence
      def self.persist(context, document)
        new(context, JSON.pretty_generate(document)).persist
      end

      def initialize(context, body)
        @context = context
        @body = body
      end

      def persist
        persist_row
        persist_file
      end

      private

      def persist_row
        @context.database(:knowledge).transaction do |batch|
          batch.put(:retrieval_discoveries, { intent_id: @context.intent_id, data: @body, updated_at: Plastic.now })
        end
      end

      def persist_file
        path = File.join(@context.scope.root, "discovery", "#{@context.intent_id}.json")
        directory = File.dirname(path)
        FileUtils.mkdir_p(directory)
        Tempfile.create(["discovery", ".json"], directory) { |file| replace(file.path, path) }
      end

      def replace(temporary, path)
        File.write(temporary, @body)
        File.rename(temporary, path)
      end
    end
  end
end
