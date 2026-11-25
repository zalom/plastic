# frozen_string_literal: true

module CommandReference
  module Markdown
    # A link to a file of the kernel, relative to the page that holds it.
    class Links
      def initialize(base)
        @base = base
      end

      def file(path) = "[`#{path.delete_prefix("lib/plastic/")}`](#{@base}#{path})"
    end
  end
end
