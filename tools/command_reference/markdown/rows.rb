# frozen_string_literal: true

module CommandReference
  module Markdown
    # A table row for one workflow of a command.
    class FlowRow
      def initialize(flow, links)
        @flow = flow
        @links = links
      end

      def to_s
        "| [#{@flow.path}](##{@flow.anchor}) | #{@flow.lane} | #{@links.code(@flow.file, @flow.line)} |"
      end
    end

    # A table row for one way a command call ends.
    class EndingRow
      def initialize(ending, links)
        @ending = ending
        @links = links
      end

      def to_s = "| #{Words.cell(@ending.text)} | #{@ending.exit_code} | #{Words.cell(@ending.next_text)} | #{@links.code(@ending.file, @ending.line)} |"
    end
  end
end
