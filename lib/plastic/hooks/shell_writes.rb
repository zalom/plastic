# frozen_string_literal: true

require "shellwords"

module Plastic
  module Hooks
    # The paths a shell command writes, as far as its words show: the target of a redirection, every argument of a
    # command that changes files (rm, mv, touch, tee and the like, sed or perl in place), the last argument of a copy,
    # the of= of dd, and every word of an inline script, given with -e or -c or on standard input. A read, such as cat or
    # grep, names no path.
    class ShellWrites
      SEGMENT = /&&|\|\||[;|&\n()]/
      REDIRECT = /(?:\d|&)?>>?\|?\s*("[^"]*"|'[^']*'|[^\s;|&<>()]+)/
      WORD = %r{[^\s'"`(),;=<>|&{}\[\]]+}

      # One simple command of the line, read from its words after any leading assignment or wrapper such as sudo.
      class Command
        VERBS = {
          wrappers: %w[sudo env command nohup time exec], all: %w[rm rmdir mv touch mkdir truncate unlink ln chmod tee],
          last: %w[cp install rsync], in_place: %w[sed perl], interpreters: %w[ruby python python3 perl node sh bash zsh]
        }.freeze
        FLAGS = { in_place: /\A-[a-zA-Z]*i|\A--in-place/, inline: %w[-e -c -] }.freeze

        def self.parse(text) = new(split(text).drop_while { |word| VERBS[:wrappers].include?(word) || word.match?(/\A\w+=/) })

        def self.split(text)
          Shellwords.split(text)
        rescue ArgumentError
          text.split
        end

        def initialize(words)
          @words = words
          @verb = File.basename(words.first.to_s)
        end

        def empty? = @words.empty?

        # The words this command writes to.
        def written
          return arguments if writes_every_argument?
          return arguments.last(1) if verb?(:last)

          (@verb == "dd") ? @words.grep(/\Aof=/).map { |word| word.delete_prefix("of=") } : []
        end

        # Whether the command runs a script it is given, with -e or -c, or on standard input from a here-document.
        def script?(line) = verb?(:interpreters) && (@words.intersect?(FLAGS[:inline]) || line.include?("<<"))

        private

        def verb?(kind) = VERBS.fetch(kind).include?(@verb)

        def arguments = @words.drop(1).reject { |word| word.start_with?("-") }

        def writes_every_argument? = verb?(:all) || (verb?(:in_place) && @words.any? { |word| word.match?(FLAGS[:in_place]) })
      end

      def self.paths(line) = new(line).paths

      def initialize(line)
        @line = line.to_s
        @commands = @line.split(SEGMENT).map { |text| Command.parse(text) }.reject(&:empty?)
      end

      def paths = [*redirected, *@commands.flat_map(&:written), *scripted].reject(&:empty?).uniq

      private

      def redirected = @line.scan(REDIRECT).flatten.map { |word| word.delete(%q("')) }

      # An inline script can write anything it names, so every word of the line counts.
      def scripted = (@commands.any? { |command| command.script?(@line) }) ? @line.scan(WORD) : []
    end
  end
end
