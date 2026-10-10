# frozen_string_literal: true

module CommandReference
  module Markdown
    # A comment turned into paragraphs and code blocks.
    class Prose
      def self.lines(comment) = Snippet.blocks(comment).flat_map { |kind, body| (kind == :code) ? ["```ruby", body, "```", ""] : [body, ""] }
    end
  end
end
