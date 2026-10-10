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

    # The stores a command declares, as keys read and written, and the schema that names their files.
    Declared = Data.define(:schema, :keys) do
      def files(mode) = keys.fetch(mode, []).filter_map { |key| schema.file_of_key(key) }

      def store(file) = ((key = schema.key_of(file)) == :local) ? :work : key
    end

    attr_reader :entries, :components, :files

    def initialize(entries:, components:, files:, schema:, declared: {})
      @entries = entries.uniq
      @components = components.uniq
      @files = files
      @declared = Declared.new(schema, declared)
    end

    def empty? = database_files.empty? && files.empty?

    def writes?(file, table) = entries.include?(Entry.new(file, table, :write))

    def reads?(file, table) = entries.include?(Entry.new(file, table, :read))

    def tables(mode) = entries.select { |entry| entry.mode == mode }.map(&:table).uniq

    def database_files = (entries.map(&:file) + @declared.files(:read) + @declared.files(:write)).uniq.sort

    def declared?(file, mode) = @declared.files(mode).include?(file) && tables_of(file, mode).empty?

    def in?(file, mode) = declared?(file, mode) || tables_of(file, mode).any?

    def tables_of(file, modes = MODES) = entries.select { |entry| entry.on?(file, Array(modes)) }.map(&:table).uniq.sort

    def store_keys(modes = MODES) = Array(modes).flat_map { |mode| keys_of(mode) }.uniq.sort

    def schema = @declared.schema

    private

    def keys_of(mode) = database_files.select { |file| in?(file, mode) }.map { |file| @declared.store(file) }.compact
  end
end
