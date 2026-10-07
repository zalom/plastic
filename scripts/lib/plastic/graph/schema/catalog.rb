# frozen_string_literal: true

require_relative "../db/schema"

module Plastic
  module Graph
    # The tables and databases that db/schema.rb declares, as the schema reads them.
    module SchemaCatalog
      TABLES = SCHEMA_FILE.tables.freeze
      VIRTUAL = SCHEMA_FILE.virtual.freeze
      MARKS = { legacy: SCHEMA_FILE.legacy.freeze, since: SCHEMA_FILE.since.freeze }.freeze
      DATABASES = SCHEMA_FILE.databases.freeze
      STORE = %i[work knowledge references].freeze
    end
  end
end
