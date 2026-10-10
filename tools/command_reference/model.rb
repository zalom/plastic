# frozen_string_literal: true

module CommandReference
  # Builds a Page for each command of the command table.
  class Model
    def initialize(root, table: Plastic::CLI::TABLE)
      source = Source.new(root)
      schema = Schema.new(root)
      scan = Touches::Scan.new(source, Touches::Facade.new(source, root), schema)
      @kit = Kit.new(source:, root:, table:, schema:, scan:, endings: Endings.new(source), prints: Prints.new(source))
    end

    def source = @kit.source

    def schema = @kit.schema

    def page(words_or_class) = CommandReading.of(@kit, words_or_class).page
  end
end
