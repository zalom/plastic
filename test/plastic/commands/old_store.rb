# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/cli/projects_file"
require_relative "../../../lib/plastic/graph/evidence/writer"

# A registered project whose store holds a document but has lost its retrieval file.
module OldStore
  OLD = "old"

  def checkout = (@checkout ||= File.realpath(Dir.mktmpdir("checkout", @home)))

  def old_store
    graphs = Plastic::Graph.create(home: @plastic_home, store: OLD)
    Plastic::Graph::Retrieval::Evidence::Writer.new(graphs.databases.fetch(:store), origin, clock: FixedClock::CLOCK).write("1", "notes.md", "old evidence")
    lose(graphs.databases.fetch(:store))
    Plastic::CLI::ProjectsFile.new(File.join(@plastic_home, "projects.yml")).add(OLD, checkout)
  end

  def lose(store)
    Plastic::Graph::Database::ConnectionPool.connections.delete(store.path)&.close
    File.delete(store.retrieval_path)
  end

  def repair = Plastic::Graph.create(home: @plastic_home, store: OLD).retrieval.repair
end
