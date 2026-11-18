# frozen_string_literal: true

require_relative "source_reader"

module Plastic
  module Graph
    module Retrieval
      # Reads the printed hashes, kept file bytes and legacy rows of the store database.
      class StoreRead < SourceReader
        def kept_file_data(name)
          row = databases.fetch(:store).row("SELECT hex(data) AS data FROM sqlar WHERE name = :name", name:)
          [row.fetch("data")].pack("H*")
        end

        def printed
          databases.fetch(:store).rows("SELECT path, sha256 FROM printed").to_h { |row| row.values_at("path", "sha256") }
        end

        def legacy_intents_data(intent_id = nil) = read(:legacy_intents_data, intent_id)
      end
    end
  end
end
