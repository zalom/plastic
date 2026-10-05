# frozen_string_literal: true

require_relative "../cli/command"
require_relative "../graph"
require_relative "../graph/knowledge/link/check"

module Plastic
  module Commands
    # Lists the links of the store whose local end names an intent or a
    # ruling the store does not hold. It writes nothing; it fails with the
    # count when any link is broken.
    class ProjectLinks < CLI::Command
      reads :knowledge

      def call
        broken = Graph::Knowledge::Link::Check.new(graphs.databases, graphs.retrieval).broken
        broken.each { |link| output.raw("#{link.from_ref} #{link.kind} #{link.to_ref}") }
        raise CLI::Command::Failure, "#{broken.size} #{(broken.size == 1) ? "link names" : "links name"} an intent or a ruling this store lacks" if broken.any?

        output.next_step("plastic status", because: "every link names an intent or a ruling this store holds")
      end
    end
  end
end
