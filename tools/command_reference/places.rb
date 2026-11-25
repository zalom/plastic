# frozen_string_literal: true

module CommandReference
  # The places a call can change, named by the keys of the words a workflow or a command declares.
  module Places
    KEYS = [*Plastic::CLI::Declarations::GRAPHS, :store, :databases, :backups, :local, :home, :harness, :claims].freeze
    WHERE = {
      work: "the work graph database, in the store folder", knowledge: "the knowledge graph database, in the store folder",
      retrieval: "the search index, in the store folder",
      claims: "the work graph database, in the store folder",
      store: "the store folder", databases: "the database files of the store, in the store folder", backups: "the backups folder, in the store folder", local: "the local database, in the home folder",
      home: "the Plastic home folder", harness: "the settings of the agent harness, in the home folder"
    }.freeze
    WITH_PRINT = %i[work knowledge].freeze
    TRAVELS = "goes with the store"
    STAYS = "stays on this machine"

    def self.known?(key) = KEYS.include?(key)

    def self.where(key) = WHERE.fetch(key)

    def self.reach(key) = { store: TRAVELS }.fetch(key, STAYS)

    def self.reach_printing(key) = WITH_PRINT.include?(key) ? TRAVELS : reach(key)
  end

  # The build stops with every word a page lacks, one line each.
  class MissingWords < StandardError
    def initialize(lines)
      super("The command pages lack words:\n#{lines.map { |line| "  #{line}" }.join("\n")}")
    end
  end
end
