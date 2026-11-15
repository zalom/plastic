# frozen_string_literal: true

module CommandReference
  # One thing a call changes, with the place it changes and how far the change travels.
  Change = Data.define(:text, :place, :where, :reach)

  # What one call changes, read from the words of its steps, its own words and its prints.
  class Changes
    PRINTED = {
      files: "The files of the intent and the index of the store are rewritten",
      index: "The index of the store is rewritten",
      roadmap: "The files of the roadmap are rewritten"
    }.freeze

    def initialize(klass, flows)
      @klass = klass
      @flows = flows
    end

    def rows = [*declared, *printed].uniq { |each| [each.text, each.place] }

    private

    def prints = Array(@klass.prints)

    def printing? = prints.any?

    def change(text, place) = Change.new(text, place, Places.where(place), Places.reach(place, printing?))

    def declared = [*steps, *(@klass.changes || {}).to_a].map { |place, text| change(text, place) }

    def steps = @flows.flat_map { |flow| flow.klass.steps.grep(Plastic::CodeWorkflow::Step).flat_map { |step| step.changes.to_a } }

    def printed = printed_texts.map { |text| change(text, :store) }

    def printed_texts
      [(PRINTED[:files] if prints.include?(:intent)), (PRINTED[:index] if prints == [:index]), (PRINTED[:roadmap] if prints.include?(:roadmap))].compact
    end
  end
end
