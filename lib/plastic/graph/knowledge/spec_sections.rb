# frozen_string_literal: true

require_relative "../../layout"

module Plastic
  module Graph
    module Knowledge
      # The sections the layout gives spec.md, and why a text cannot be the whole spec: the sections it lacks.
      module SpecSections
        HEADINGS = Layout.file(:spec).headings

        module_function

        # The names of the sections the text has no heading for, under any of their names.
        def missing(text)
          lines = text.each_line.map(&:chomp)
          HEADINGS.reject { |heading| lines.grep(heading.pattern).any? }.map(&:name)
        end

        # Why the text cannot be the whole spec.md, or nil.
        def problem(text)
          gaps = missing(text)
          "the spec lacks the #{gaps.one? ? "section" : "sections"} #{joined(gaps)}; spec.md holds the sections #{joined(HEADINGS.map(&:name))}" if gaps.any?
        end

        def joined(words) = [words[0...-1].join(", "), words.last].reject(&:empty?).join(" and ")
      end
    end
  end
end
