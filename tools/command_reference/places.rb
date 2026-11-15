# frozen_string_literal: true

module CommandReference
  # The places a call can change, named by the keys of the words a workflow or a command declares.
  module Places
    KEYS = [*Plastic::CLI::Declarations::GRAPHS, :store, :backups, :local, :home, :harness].freeze

    def self.known?(key) = KEYS.include?(key)
  end

  # The build stops with every word a page lacks, one line each.
  class MissingWords < StandardError
    def initialize(lines)
      super("The command pages lack words:\n#{lines.map { |line| "  #{line}" }.join("\n")}")
    end
  end
end
