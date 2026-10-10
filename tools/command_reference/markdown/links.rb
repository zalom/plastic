# frozen_string_literal: true

module CommandReference
  module Markdown
    # A link to a line of the kernel, relative to the page that holds it.
    class Links
      def initialize(base)
        @base = base
      end

      def code(file, line) = "[`#{File.basename(file)}:#{line}`](#{@base}#{file}#L#{line})"

      def at(place) = code(*place.to_h.values_at(:file, :line))

      def file(path) = "[`#{path.delete_prefix("scripts/lib/plastic/")}`](#{@base}#{path})"
    end
  end
end
