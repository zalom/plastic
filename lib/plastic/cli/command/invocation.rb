# frozen_string_literal: true

require_relative "../parser"

module Plastic
  class CLI
    class Command
      # The call as typed: the argv, the words that named it and the tool that
      # parses it. The parse happens once.
      class Invocation
        attr_reader :argv, :words

        def initialize(argv, words, tool)
          @argv = argv.dup
          @words = words
          @tool = tool
          @parsed = nil
        end

        def usage_line = @tool.usage_line(words)

        def parsed
          @parsed ||= Parser.new(arguments: @tool.arguments, options: @tool.options, banner: usage_line).parse(argv)
        end

        def json? = argv.include?("--json")

        def help? = argv.intersect?(%w[--help -h])

        def project_named? = argv.grep(/\A--project(?:=|$)/).any?
      end
    end
  end
end
