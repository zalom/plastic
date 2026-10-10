# frozen_string_literal: true

module CommandReference
  # The databases, tables, parts and files one command touches.
  class Touches
    MODES = %i[read write].freeze

    # One table of one database file, read or written.
    Entry = Data.define(:file, :table, :mode) do
      def on?(database, modes) = modes.include?(mode) && file.eql?(database)
    end
    # One part of the code that a command reaches, with its file.
    Part = Data.define(:name, :file)

    attr_reader :entries, :components, :files, :schema

    def initialize(entries:, components:, files:, schema:)
      @entries = entries.uniq
      @components = components.uniq
      @files = files
      @schema = schema
    end

    def empty? = entries.empty? && files.empty?

    def writes?(file, table) = entries.include?(Entry.new(file, table, :write))

    def reads?(file, table) = entries.include?(Entry.new(file, table, :read))

    def tables(mode) = entries.select { |entry| entry.mode == mode }.map(&:table).uniq

    def database_files = entries.map(&:file).uniq.sort

    def tables_of(file, modes = MODES) = entries.select { |entry| entry.on?(file, Array(modes)) }.map(&:table).uniq.sort

    def store_keys = database_files.filter_map { |file| schema.key_of(file) }.reject { |key| key == :local }
  end
end
