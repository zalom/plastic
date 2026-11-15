# frozen_string_literal: true

module CommandReference
  # Builds a Page for each command of the command table.
  class Model
    def initialize(root, table: Plastic::CLI::TABLE)
      source = Source.new(root)
      @kit = Kit.new(source:, root:, table:, endings: Endings.new(source))
    end

    def source = @kit.source

    def page(words_or_class) = CommandReading.of(@kit, words_or_class).page
  end
end
