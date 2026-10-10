# frozen_string_literal: true

module CommandReference
  # The databases, tables, parts and files one command touches.
  class Touches
    Entry = Data.define(:file, :table, :mode)
    Part = Data.define(:name, :file)

    attr_reader :entries, :components, :files, :schema

    def initialize(entries:, components:, files:, schema:)
      @entries = entries.uniq
      @components = components.uniq
      @files = files
      @schema = schema
    end

    def empty? = entries.empty? && files.empty?

    def writes?(file, table) = held?(file, table, :write)

    def reads?(file, table) = held?(file, table, :read)

    def tables(mode) = entries.select { |entry| entry.mode == mode }.map(&:table).uniq

    def database_files = entries.map(&:file).uniq.sort

    def tables_of(file, mode = nil)
      entries.select { |entry| entry.file == file && (mode.nil? || entry.mode == mode) }.map(&:table).uniq.sort
    end

    def store_keys = database_files.filter_map { |file| schema.key_of(file) }.reject { |key| key == :local }

    private

    def held?(file, table, mode) = entries.any? { |entry| entry.file == file && entry.table == table && entry.mode == mode }
  end
end
