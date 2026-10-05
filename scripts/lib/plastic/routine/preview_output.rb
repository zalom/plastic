# frozen_string_literal: true

require "delegate"

module Plastic
  class Routine < CLI::Command
    # The output of a previewed call. Every printed line says it is a preview
    # and names the original path, never the copy's; the rows say what the
    # call would write; the next: command is the same call without --dry-run.
    class PreviewOutput < SimpleDelegator
      CLOSING = "preview complete; the original store was not changed"
      BECAUSE = "the preview wrote only to a disposable copy"

      def initialize(output, copy, command)
        super(output)
        @copy = copy
        @command = command
      end

      def raw(text) = tap { @copy.original(text).lines(chomp: true).each { |line| __getobj__.raw("preview: #{line}") } }

      def row(label, value) = tap { __getobj__.row((label == "wrote:") ? "would write:" : label, value) }

      def next_step(*, **) = tap { __getobj__.next_step(@command, because: BECAUSE) }

      # The files the call would add, change or remove, then the closing line.
      def show(changes)
        changes.each { |verb, path| __getobj__.raw("preview: #{verb} #{path}") }
        __getobj__.raw(CLOSING)
      end
    end
  end
end
