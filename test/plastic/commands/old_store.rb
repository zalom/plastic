# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/cli/projects_file"
require_relative "../../../lib/plastic/graph/retrieval/evidence/writer"

# A registered project whose store holds a document but has lost its retrieval file.
module OldStore
  OLD = "old"

  def checkout = (@checkout ||= File.realpath(Dir.mktmpdir("checkout", @home)))

  def old_store
    graphs = Plastic::Graph.create(home: @plastic_home, store: OLD)
    Plastic::Graph::Retrieval::Evidence::Writer.new(graphs.databases.fetch(:knowledge), origin).write("1", "notes.md", "old evidence")
    lose(graphs.databases.fetch(:retrieval).path)
    Plastic::CLI::ProjectsFile.new(File.join(@plastic_home, "projects.yml")).add(OLD, checkout)
  end

  def lose(path)
    Plastic::Graph::Database::ConnectionPool.connections.delete(path)&.close
    File.delete(path)
  end

  def repair = Plastic::Graph.create(home: @plastic_home, store: OLD).retrieval.repair
end
