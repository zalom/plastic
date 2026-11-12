# frozen_string_literal: true

require "prism"

module CommandReference
  module Markdown
    # The statements of a command's own call, one numbered item each, with the line that holds it.
    class CallSteps
      def initialize(own, links)
        @own = own
        @links = links
      end

      def lines = statements.each_with_index.map { |node, at| "#{at + 1}. #{Words.span(node.location.slice)} #{@links.code(@own.file, line_of(node))}" }

      private

      def line_of(node) = @own.line + node.location.start_line - 1

      def statements
        body = Prism.parse(@own.code.join("\n")).value.statements.body.first.body
        body.is_a?(Prism::BeginNode) ? guarded(body) : Array(body&.body)
      end

      def guarded(body) = [*body.statements&.body, body.rescue_clause, body.else_clause, body.ensure_clause].compact
    end
  end
end
