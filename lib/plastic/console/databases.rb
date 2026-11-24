# frozen_string_literal: true

require "sqlite3"
require_relative "../errors"
require_relative "../graph/schema"
require_relative "../graph/missing_store"

module Plastic
  module Console
    # The databases the console reads: the three files of one store and the
    # machine-wide plastic.db, each its own read-only connection under the
    # name of its file: work, knowledge, retrieval and plastic. Opening writes
    # nothing: every file must exist already, and no pragma sets a value.
    class Databases
      NAMES = %i[work knowledge retrieval plastic].freeze
      KEYS = { work: :work, knowledge: :knowledge, retrieval: :retrieval, plastic: :local }.freeze
      BUSY_MILLISECONDS = 5000

      attr_reader(*NAMES)

      # The databases of the store the scope names.
      def self.open(scope)
        raise Graph::MissingStore, scope.slug unless File.directory?(scope.root)

        paths = KEYS.transform_values { |key| File.join(key == :local ? scope.plastic_home : scope.root, Graph::Schema.file(key)) }
        missing = paths.values.reject { |path| File.file?(path) }
        raise Failed, "the console needs #{missing.map { |path| File.basename(path) }.join(", ")}, which #{scope.root} does not hold" unless missing.empty?

        new(paths.transform_values { |path| connect(path) })
      end

      def self.connect(path)
        SQLite3::Database.new(path, readonly: true, results_as_hash: true).tap { |database| database.busy_timeout = BUSY_MILLISECONDS }
      end

      def initialize(connections)
        connections.each { |name, connection| instance_variable_set(:"@#{name}", connection) }
      end

      # Runs the code with the four names in reach, and gives its value.
      def evaluate(code) = instance_eval(code, "(console)", 1)

      def close = NAMES.each { |name| public_send(name).close }
    end
  end
end
