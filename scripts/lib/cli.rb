# encoding: UTF-8
# frozen_string_literal: true

require "did_you_mean"
require_relative "cli/table"
require_relative "cli/command"
require_relative "cli/output"

# Plastic::CLI (intent 363) - the dispatcher behind bin/plastic. It reads the
# command table, matches the longest command name the arguments begin with,
# requires that one file, and calls it. Nothing else is loaded, which is what
# keeps a call at about 20 milliseconds with RubyGems off.
#
# No arguments, or --help, print the command list. --version prints the
# version. A command's own --help prints that command's usage line, read from
# the class without building it. An unknown name exits 2 and names the closest
# command, so a typo never becomes a stack trace.
module Plastic
  class CLI
    FLAGS = {"--version" => "version", "-v" => "version",
             "--help" => "help", "-h" => "help"}.freeze

    def self.call(...)
      new(...).call
    end

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

    def call
      matched = match(expanded)
      return unknown(expanded.first) unless matched

      name, rest = matched
      return usage(name, rest) if help?(rest)

      command(name).call(rest, out: @out, err: @err, env: @env, home: @home,
        directory: @directory)
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

    def help?(rest)
      rest.any? { |argument| FLAGS[argument] == "help" }
    end

    def usage(name, rest)
      Output.new(out: @out, err: @err)
        .row("usage", command(name)::USAGE_LINE)
        .flush(json: rest.include?("--json"))
      Command::OK
    end

    def command(name)
      file, const, = @table.fetch(name)
      require_relative "cli/#{file}"
      Commands.const_get(const)
    end

    def unknown(name)
      suggestions = closest(name)
      @err.puts "plastic: no command named #{name.inspect}"
      @err.puts "Closest: #{suggestions.join(", ")}" unless suggestions.empty?
      @err.puts "Run `plastic help` for the command list."
      Command::USAGE
    end

    def closest(name)
      DidYouMean::SpellChecker.new(dictionary: @table.keys).correct(name)
    end
  end
end
