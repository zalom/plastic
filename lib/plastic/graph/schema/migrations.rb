# frozen_string_literal: true

module Plastic
  module Graph
    # The SQL file of each migration sequence.
    module SchemaMigrations
      FOLDER = File.join(__dir__, "migrations")

      PATHS = {
        store: File.join(FOLDER, "store_from_beta_2.sql"),
        home: File.join(FOLDER, "plastic_db_from_local_db.sql")
      }.freeze

      def self.path(sequence) = PATHS.fetch(sequence)
    end
  end
end
