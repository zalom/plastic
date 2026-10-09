# frozen_string_literal: true

require_relative "../cli/command"
require_relative "../graph"
require_relative "../graph/knowledge/link/check"

module Plastic
  module Commands
    # Lists the links of the store whose local end names an intent or a
    # ruling the store does not hold. It writes nothing; it prints the
    # count when any link is broken.
    class ProjectLinks < CLI::Command
      reads :knowledge

      def call
        broken = broken_links
        broken.each { |link| output.raw("#{link.from_ref} #{link.kind} #{link.to_ref}") }
        output.raw(broken_line(broken.size)) if broken.any?
        output.next_step("plastic status", because: "every link names an intent or a ruling this store holds")
      end

      private

      def broken_links = Graph::Knowledge::Link::Check.new(graphs.databases, graphs.retrieval).broken

      def broken_line(count)
        noun = (count == 1) ? "link names" : "links name"
        "#{count} #{noun} an intent or a ruling this store lacks"
      end
    end
  end
end
