# frozen_string_literal: true

module CommandReference
  # The tables of each database file, read from the schema file.
  class Schema
    BOOKKEEPING = %w[changes printed].freeze
    DATABASE_LINE = /^\s*database :(\w+), "([^"]+)", %i\[([^\]]+)\]/m

    def initialize(root)
      @text = File.read(File.join(root, "scripts/lib/plastic/graph/db/schema.rb"))
    end

    def files = databases.values.map(&:first)

    def tables = databases.values.flat_map(&:last).uniq - BOOKKEEPING

    def file_of(table) = databases.values.find { |_file, held| held.include?(table) }&.first

    def key_of(file) = databases.find { |_key, (name, _held)| name == file }&.first

    private

    def databases
      @databases ||= @text.scan(DATABASE_LINE).to_h { |key, file, held| [key.to_sym, [file, held.split]] }
    end
  end
end
