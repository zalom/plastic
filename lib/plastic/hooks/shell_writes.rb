# frozen_string_literal: true

require "shellwords"
require_relative "shell_folder"

module Plastic
  module Hooks
    # The paths a shell command writes, as far as its words show: the target of a redirection, every argument of a
    # command that changes files (rm, mv, touch, tee and the like, sed or perl in place), the last argument of a copy,
    # the of= of dd, and every word of an inline script, given with -e or -c, on standard input or in a here-document.
    # A relative path is read from the folder the cd words before it move to. A read, such as cat or grep, names no
    # path, and a program file, such as ruby tool.rb, is not read.
    class ShellWrites
      SEPARATOR = /(&&|\|\||[;|&\n()])/
      REDIRECT = /(?:\d|&)?>>?\s*("[^"]*"|'[^']*'|[^\s;|&<>()]+)/
      WORD = %r{[^\s'"`(),;=<>|&{}\[\]]+}

      # One simple command of the line, read from its words after any leading assignment or wrapper such as sudo.
      class Command
        VERBS = {
          wrappers: %w[sudo env command nohup time exec], all: %w[rm rmdir mv touch mkdir truncate unlink ln chmod tee],
          last: %w[cp install rsync], in_place: %w[sed perl],
          interpreters: %w[ruby python perl node bun sh bash zsh dash ksh fish osascript]
        }.freeze
        FLAGS = { in_place: /\A-[a-zA-Z]*i|\A--in-place/, inline: /\A(?:-|--eval|-[a-zA-Z]*[ec])\z/ }.freeze

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

        # The folder a cd moves to: its argument, or the home folder when it has none; nil for any other command and
        # for cd -, whose folder the words do not show.
        def folder
          return unless @verb == "cd" && !@words.include?("-")

          arguments.first || "~"
        end

        # Whether the command runs a script it is given: with an inline flag such as -e, -c or --eval, on standard
        # input with no script file named, or from a here-document.
        def script?(line)
          interpreter? && (@words.any? { |word| word.match?(FLAGS[:inline]) } || arguments.empty? || line.include?("<<"))
        end

        private

        def verb?(kind) = VERBS.fetch(kind).include?(@verb)

        # An interpreter by name, with any version after it, such as python3.12.
        def interpreter? = VERBS[:interpreters].include?(@verb.sub(/[\d.]+\z/, ""))

        def arguments = @words.drop(1).reject { |word| word.start_with?("-") }

        def writes_every_argument? = verb?(:all) || (verb?(:in_place) && @words.any? { |word| word.match?(FLAGS[:in_place]) })
      end

      def self.paths(line) = new(line).paths

      def initialize(line)
        @line = line.to_s
        @folder = ShellFolder.new
        @found = []
        @line.gsub(">|", ">").split(SEPARATOR).each { |piece| read(piece) }
      end

      def paths = @found.uniq

      private

      def read(piece)
        case piece
        when "(" then @folder.enter
        when ")" then @folder.leave
        when SEPARATOR then nil
        else segment(piece)
        end
      end

      def segment(text)
        command = Command.parse(text)
        words = [*text.scan(REDIRECT).flatten.map { |word| word.delete(%q("')) }, *command.written, *scripted(command)]
        @found.concat(words.reject(&:empty?).map { |word| @folder.resolve(word) })
        target = command.folder
        @folder.change(target) if target
      end

      # An inline script can write anything it names, so every word of the line counts.
      def scripted(command) = command.script?(@line) ? @line.scan(WORD) : []
    end
  end
end
