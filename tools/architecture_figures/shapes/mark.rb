# frozen_string_literal: true

module ArchitectureFigures
  module Shapes
    # A glyph for writes, reads or prints, followed by a few words.
    class Mark < Data.define(:left, :top, :verb, :text)
      def markup(_id) = [glyph, Shapes.text([left + 18, top], "s", text)].join("\n")

      private

      def glyph
        ink = Palette.color(:ink)
        case verb
        when :writes then dot(%(r="4" fill="#{ink}"))
        when :reads then dot(%(r="3.5" fill="none" stroke="#{ink}" stroke-width="1.4"))
        else %(<rect x="#{left + 1}" y="#{top - 8}" width="8" height="8" fill="none" stroke="#{ink}" stroke-width="1.4"/>)
        end
      end

      def dot(attributes) = %(<circle cx="#{left + 5}" cy="#{top - 4}" #{attributes}/>)
    end
  end
end
