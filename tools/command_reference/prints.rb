# frozen_string_literal: true

module CommandReference
  # The files a command prints from the rows it writes, read from the file list in the prints code.
  class Prints
    FILE = "lib/plastic/graph/prints.rb"
    LISTED = /^\s*# - (store\/\S+)/
    ROADMAP = /Print\.text\("(roadmaps\/[^"]*)"/
    KINDS = { intent: %r{store/index\.json|ID--SLUG}, roadmap: %r{roadmaps}, index: %r{store/index\.json} }.freeze

    def initialize(source)
      @lines = source.lines(FILE)
    end

    def files(kinds) = located(kinds).keys

    # Each file the kinds print, with the line of the prints code that names it.
    def located(kinds) = kinds.flat_map { |kind| of(kind) }.uniq(&:first).to_h

    private

    def listed = @listed ||= @lines.each_with_index.filter_map { |text, at| [text[LISTED, 1], at + 1] if text.match?(LISTED) }

    def roadmap = @roadmap ||= @lines.each_with_index.filter_map { |text, at| [text[ROADMAP, 1].sub("\#{slug}", "SLUG"), at + 1] if text.match?(ROADMAP) }

    def of(kind) = (listed + roadmap).grep(->(pair) { KINDS.fetch(kind).match?(pair.first) })
  end
end
