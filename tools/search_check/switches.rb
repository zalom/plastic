# frozen_string_literal: true

require "optparse"

module SearchCheck
  # Reads the options of a call into the hash it is given.
  class Switches
    def initialize(found)
      @found = found
    end

    def parse(argv) = parser.parse(argv)

    private

    def parser
      OptionParser.new.tap do |parser|
        parser.on("--keywords") { @found[:field] = :keywords }
        parser.on("--limit N", Integer) { |number| @found[:limit] = number }
        parser.on("--store DIR") { |folder| @found[:store] = folder }
      end
    end
  end
end
