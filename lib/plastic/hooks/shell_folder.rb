# frozen_string_literal: true

module Plastic
  module Hooks
    # The folder a shell command runs in, as far as its cd words show, with one level for each subshell. Nil stands for
    # the folder the hook was given; a relative path is read from it later.
    class ShellFolder
      ROOTED = %w[/ ~ $].freeze

      def initialize
        @levels = [nil]
      end

      # A subshell starts in the folder of the shell around it.
      def enter = @levels.push(@levels.last)

      # The end of a subshell takes the folder back to the one before it.
      def leave = (@levels.size > 1) && @levels.pop

      def change(target) = @levels[-1] = resolve(target)

      # The word as a path read from the current folder: a rooted word as it is, any other word joined to the folder.
      def resolve(word)
        folder = @levels.last
        (folder.nil? || word.start_with?(*ROOTED)) ? word : File.join(folder, word)
      end
    end
  end
end
