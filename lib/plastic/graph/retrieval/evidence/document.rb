# frozen_string_literal: true

require "digest"
require_relative "text"

module Plastic
  module Graph
    module Retrieval
      class Evidence
        # Represents one document with its computed revision and extracted passages.
        class Document
          # Stores immutable computed fields for one document write.
          Record = Data.define(:intent_id, :path, :body, :revision, :extraction, :passages, :now)

          def initialize(intent_id, path, body, now: Plastic.now)
            extraction = Evidence::Text.extract_with_lines(path, body)
            @record = Record.new(intent_id, path, body, Digest::SHA256.hexdigest(body), extraction, Evidence::Text.passages(extraction), now)
          end

          def intent_id = @record.intent_id
          def path = @record.path
          def body = @record.body
          def revision = @record.revision
          def passages = @record.passages

          def document_row = { intent_id:, path:, body:, updated_at: @record.now }
          def revision_row(origin_id) = { sha256: revision, intent_id:, path:, body:, created_at: @record.now, origin_id: }
          def head_row = { intent_id:, path:, sha256: revision, updated_at: @record.now }
        end
      end
    end
  end
end
