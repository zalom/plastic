# frozen_string_literal: true

module CommandReference
  module Dsl
    # Shared by the sections of the DSL page: a heading, a drawing, and links into the kernel.
    class Section
      def initialize(dsl, links)
        @dsl = dsl
        @links = links
      end

      private

      attr_reader :dsl, :links

      def link(key, pattern) = links.code(DslPage::FILES.fetch(key), dsl.line(key, pattern))

      def opening(title, image, alt) = ["---", "", "## #{title}", "", "![#{alt}](#{image})", ""]
    end
  end
end
