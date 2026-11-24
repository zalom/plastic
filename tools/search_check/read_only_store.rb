# frozen_string_literal: true

require "sqlite3"

require_relative "usage"

module SearchCheck
  # The knowledge and retrieval files of one store, opened read-only. It answers the two calls Search makes of a store.
  class ReadOnlyStore
    KNOWLEDGE = "knowledge_graph.db"
    RETRIEVAL = "retrieval_graph.db"

    def initialize(folder)
      files = [KNOWLEDGE, RETRIEVAL].map { |name| File.join(folder, name) }
      raise Usage, "no store at #{folder}" unless files.all? { |file| File.file?(file) }

      @connection = SQLite3::Database.new(files.first, readonly: true, results_as_hash: true)
      @connection.execute("ATTACH ? AS retrieval", files.last)
    end

    def retrieval_present? = true

    def rows(sql, **binds) = @connection.execute(sql, binds)

    # The one origin whose documents the store holds.
    def origin_id = self.class.single(rows("SELECT DISTINCT origin_id FROM document_heads").map { |row| row.fetch("origin_id") })

    def self.single(ids) = ids.one? ? ids.first : raise(Usage, "the store holds #{ids.size} origins, not one")
  end
end
