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

      RUN_ROW = "1 routine run in local.db"

      def row(label, value) = tap { (label == "wrote:") ? would_write(value) : __getobj__.row(label, value) }

      def next_step(*, **) = tap { __getobj__.next_step(@command, because: BECAUSE) }

      # The files the call would add, change or remove, then the closing line.
      def show(changes)
        changes.each { |verb, path| __getobj__.raw("preview: #{verb} #{path}") }
        __getobj__.raw(CLOSING)
      end

      private

      def would_write(phrases) = __getobj__.row("would write:", [RUN_ROW, *Array(phrases)])
    end
  end
end
