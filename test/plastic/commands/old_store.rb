# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/cli/projects_file"
require_relative "../../../scripts/lib/plastic/graph/retrieval/evidence/writer"

# A registered project whose store holds a document but no retrieval backfill
# marker, as a store made before the marker existed does.
module OldStore
  OLD = "old"

  def checkout = (@checkout ||= File.realpath(Dir.mktmpdir("checkout", @home)))

  def old_store
    FileUtils.mkdir_p(File.join(@plastic_home, "stores", OLD))
    graphs = Plastic::Graph.open(home: @plastic_home, store: OLD)
    Plastic::Graph::Retrieval::Evidence::Writer.new(graphs.databases.fetch(:knowledge), origin).write("1", "notes.md", "old evidence")
    graphs.databases.each_value { |database| database.rows("SELECT 1") }
    Plastic::CLI::ProjectsFile.new(File.join(@plastic_home, "projects.yml")).add(OLD, checkout)
  end

  def repair = plastic("project", "new", OLD, checkout, table: Plastic::CLI::TABLE)
end
