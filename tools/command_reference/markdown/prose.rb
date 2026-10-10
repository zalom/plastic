# frozen_string_literal: true

module CommandReference
  module Markdown
    # A comment turned into paragraphs and code blocks.
    class Prose
      SHARED = 0.75
      LONGER = 2

      def self.lines(comment) = Snippet.blocks(comment).flat_map { |kind, body| (kind == :code) ? ["```ruby", body, "```", ""] : [body, ""] }

      def self.repeats?(summary, comment)
        small, large = [words(summary), words(Array(comment).join(" "))].sort_by(&:size)
        small.any? && large.size <= LONGER * small.size && (small & large).size >= SHARED * small.size
      end

      def self.words(text) = text.to_s.downcase.scan(/[a-z]+/).map { |word| word.delete_suffix("s") }.uniq
    end
  end
end
