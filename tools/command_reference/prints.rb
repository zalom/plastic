# frozen_string_literal: true

module CommandReference
  # The files a command prints from the rows it writes, read from the file list in the prints code.
  class Prints
    FILE = "scripts/lib/plastic/graph/prints.rb"
    LISTED = /^\s*# - (store\/\S+)/
    ROADMAP = /Print\.text\("(roadmaps\/[^"]*)"/
    KINDS = { intent: %r{store/index\.json|ID--SLUG}, roadmap: %r{roadmaps}, index: %r{store/index\.json} }.freeze

    def initialize(source)
      @lines = source.lines(FILE)
    end

    def files(kinds) = kinds.flat_map { |kind| of(kind) }.uniq

    private

    def listed = @listed ||= @lines.filter_map { |text| text[LISTED, 1] }

    def roadmap = @roadmap ||= @lines.filter_map { |text| text[ROADMAP, 1]&.sub("\#{slug}", "SLUG") }

    def of(kind) = (listed + roadmap).grep(KINDS.fetch(kind))
  end
end
