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

    def change(text, place) = Change.new(text, place, Places.where(place), reach(place))

    def reach(place) = printing? ? Places.reach_printing(place) : Places.reach(place)

    def declared = [*steps, *(@klass.changes || {}).to_a].flat_map { |place, text| changes_at(place, text) }

    def changes_at(place, text) = Array(text).map { |each| change(each, place) }

    def steps = @flows.flat_map(&:step_changes)

    def printed = printed_texts.map { |text| change(text, :store) }

    def printed_texts
      [(PRINTED[:files] if prints.include?(:intent)), (PRINTED[:index] if prints == [:index]), (PRINTED[:roadmap] if prints.include?(:roadmap))].compact
    end
  end
end
