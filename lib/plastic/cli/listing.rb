# frozen_string_literal: true

module Plastic
  class CLI
    # The shipped commands grouped in families: the core commands first, then a
    # heading and the commands of each family. With --json, a list of families.
    # A family word lists that family alone.
    class Listing
      CORE = "core"
      INDENT = "  "

      def initialize(environment, table)
        @environment = environment
        @families = FAMILIES.keys.to_h { |family| [family, table.select { |words, _| CLI.family_of(words) == family }] }.reject { |_, rows| rows.empty? }
      end

      def call(argv, only: nil)
        families = only ? @families.slice(only) : @families
        argv.include?("--json") ? json(families) : text(families)
        Command::OK
      end

      private

      def json(families)
        list = families.map { |family, rows| { "family" => family, "commands" => rows.map { |words, (_, summary)| { "command" => words, "summary" => summary } } } }
        JsonOutput.new(out: @environment.out, err: @environment.err).document({ "result" => list, "next" => nil, "because" => nil })
      end

      def text(families)
        width = families.values.flat_map(&:keys).map(&:length).max.to_i + 2
        families.each_with_index { |(family, rows), index| @environment.out.puts(*block(family, rows, width, index)) }
      end

      def block(family, rows, width, index)
        lines = rows.map { |words, (_, summary)| "#{words.ljust(width)}#{summary}" }
        return lines if family == CORE

        [*(index.zero? ? [] : [""]), "#{family}:", *lines.map { |line| "#{INDENT}#{line}" }]
      end
    end
  end
end
