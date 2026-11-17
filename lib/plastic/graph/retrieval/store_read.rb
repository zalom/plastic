# frozen_string_literal: true

module Plastic
  module Graph
    module Retrieval
      # Reads stored archive and backup records without loading file bytes unless needed.
      class StoreRead
        def initialize(databases)
          @databases = databases
        end

        def kept_file_data(name)
          row = databases.fetch(:store).row("SELECT hex(data) AS data FROM sqlar WHERE name = :name", name:)
          [row.fetch("data")].pack("H*")
        end

        def printed
          databases.fetch(:store).rows("SELECT path, sha256 FROM printed").to_h { |row| row.values_at("path", "sha256") }
        end

        private

        attr_reader :databases
      end
    end
  end
end
