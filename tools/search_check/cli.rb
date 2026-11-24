# frozen_string_literal: true

require_relative "usage"
require_relative "arguments"
require_relative "check"

module SearchCheck
  # Runs every question and prints one line each and a total. Exit 0 ran, 2 called wrongly.
  class CLI
    def initialize(argv, out:, err:, home:)
      @argv = argv
      @home = home
      @streams = [out, err]
    end

    def call
      arguments = Arguments.parse(@argv, @home)
      report(arguments, arguments.questions)
      0
    rescue Usage, OptionParser::ParseError => error
      @streams.last.puts "search-check: #{error.message}"
      2
    end

    private

    def report(arguments, questions) = @streams.first.puts(Check.new(arguments, questions).lines)
  end
end
