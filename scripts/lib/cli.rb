# encoding: UTF-8
# frozen_string_literal: true

require_relative "cli/table"
require_relative "cli/command"

# Plastic::CLI (intent 363) - the dispatcher behind bin/plastic. It reads the
# command table, matches the longest command name the arguments begin with,
# requires that one file, and runs it. Nothing else is loaded, which is what
# keeps a call at about 20 milliseconds with RubyGems off.
#
# No arguments, or --help, print the command list. --version prints the
# version. An unknown name exits 2 and names the closest command, so a typo
# never becomes a stack trace.
module Plastic
  class CLI
    FLAGS = {"--version" => "version", "-v" => "version",
             "--help" => "help", "-h" => "help"}.freeze

    def initialize(argv, out: $stdout, err: $stderr, env: ENV, home: Dir.home,
      directory: Dir.pwd, table: TABLE)
      @argv = argv.dup
      @out = out
      @err = err
      @env = env
      @home = home
      @directory = directory
      @table = table
    end

    def run
      matched = match(expanded)
      return unknown(expanded.first) unless matched

      name, rest = matched
      build(name, rest).run
    end

    def match(argv)
      [2, 1].each do |width|
        name = argv.first(width).join(" ")
        return [name, argv.drop(width)] if @table.key?(name)
      end
      nil
    end

    private

    def expanded
      return ["help"] if @argv.empty?

      [FLAGS.fetch(@argv.first, @argv.first)] + @argv.drop(1)
    end

    def build(name, rest)
      file, const, = @table.fetch(name)
      require_relative "cli/#{file}"
      Commands.const_get(const).new(rest, out: @out, err: @err, env: @env, home: @home,
        directory: @directory)
    end

    def unknown(name)
      @err.puts "plastic: no command named #{name.inspect}"
      @err.puts "Closest: #{closest(name).join(", ")}" unless closest(name).empty?
      @err.puts "Run `plastic help` for the command list."
      Command::USAGE
    end

    def closest(name)
      @table.keys.select { |candidate| candidate.start_with?(name[0, 2].to_s) || distance(candidate, name) <= 2 }
    end

    def distance(left, right)
      (left.chars - right.chars).length + (right.chars - left.chars).length +
        (left.length - right.length).abs
    end
  end
end
