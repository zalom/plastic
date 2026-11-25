# frozen_string_literal: true

require_relative "../db/schema"

module Plastic
  module Graph
    # The tables and databases that db/schema.rb declares, as the schema reads them.
    module SchemaCatalog
      TABLES = SCHEMA_FILE.tables.freeze
      VIRTUAL = SCHEMA_FILE.virtual.freeze
      DATABASES = SCHEMA_FILE.databases.freeze

      def self.since = SCHEMA_FILE.since.freeze

      def self.store = %i[work knowledge]

      def self.derived = %i[retrieval]
    end
  end
end
