# frozen_string_literal: true

require_relative "../invalid"

module Plastic
  module Graph
    # A Luhmann id alternates number and letter: 307 gives 307a, 307a gives
    # 307a1. A root is a number alone, and the parent of an id is the id
    # with its last run taken off.
    module LuhmannId
      # The id split into its runs, for sorting: 307 < 307a < 307a1 < 308.
      def self.segments(id) = id.to_s.scan(/\d+|[a-z]+/).map { |part| part.match?(/\d/) ? [0, part.to_i] : [1, part] }

      def self.next_child(parent, taken)
        free = children(parent).find { |candidate| !taken.include?(candidate) }
        free or raise Invalid, "#{parent} has no free child id"
      end

      # Every child id `parent` can take, in order.
      def self.children(parent)
        suffixes = parent.to_s.match?(/[a-z]\z/) ? (1..99).map(&:to_s) : ("a".."z").to_a
        suffixes.map { |suffix| "#{parent}#{suffix}" }
      end

      def self.next_root(taken) = (taken.grep(/\A\d+\z/).map(&:to_i).max.to_i + 1).to_s

      def self.parent_of(id)
        runs = id.to_s.scan(/\d+|[a-z]+/)
        runs[0..-2].join if runs.size > 1
      end
    end
  end
end
