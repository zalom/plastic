# frozen_string_literal: true

module CommandReference
  # The words a page lacks about what its call changes.
  class ChangeWords
    def initialize(page, flows)
      @page = page
      @flows = flows
    end

    def lines = [*empty_lines, *unwritten_lines, *place_lines]

    private

    def empty_lines = (@flows.empty? && @page.klass.changes.nil?) ? ["needs changes, the words of what a call changes, or an empty hash"] : []

    def unwritten_lines
      writes = @page.klass.writes
      (writes.empty? || changed.any?) ? [] : ["writes #{writes.join(", ")} but has no change in words; add changes"]
    end

    def place_lines = changed.keys.reject { |key| Places.known?(key) }.map { |key| "change at #{key} is no known place" }

    def changed
      @changed ||= [*@flows.flat_map { |flow| flow.klass.steps.grep(Plastic::CodeWorkflow::Step).map(&:changes) }, @page.klass.changes]
        .compact.reduce({}) { |all, each| all.merge(each) }
    end
  end
end
