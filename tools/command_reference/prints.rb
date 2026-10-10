# frozen_string_literal: true

module CommandReference
  # The files a command prints from the rows it writes, read from the file list in the prints code.
  class Prints
    FILE = "scripts/lib/plastic/graph/prints.rb"
    LISTED = /^\s*# - (store\/\S+)/
    KINDS = { intent: %r{store/index\.json|ID--SLUG}, roadmap: %r{roadmaps}, index: %r{store/index\.json} }.freeze

    def initialize(source)
      @listed = source.lines(FILE).filter_map { |text| text[LISTED, 1] }
      @roadmap = source.lines(FILE).filter_map { |text| text[/Print\.text\("(roadmaps\/[^"]*)"/, 1]&.sub("\#{slug}", "SLUG") }
    end

    def files(kinds) = kinds.flat_map { |kind| of(kind) }.uniq

    private

    def of(kind) = (@listed + @roadmap).grep(KINDS.fetch(kind))
  end
end
