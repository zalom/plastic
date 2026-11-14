# frozen_string_literal: true

require_relative "../failed"

module Plastic
  class Routine < CLI::Command
    # The refusal of a call that would print a file a person changed by hand.
    module HandEditRefusal
      # A file sync up reads is cleared by sync up; one it cannot read, by printing it again from its rows.
      def self.call(path, reason) = reason ? unreadable(path, reason) : changed(path)

      def self.changed(path)
        Failed.new(workflow: :print, step: "files", reason: Graph::Prints.hand_edit_line(path), next_command: "plastic sync up", because: "a file changed by hand is read into rows before a call prints it")
      end

      def self.unreadable(path, reason)
        Failed.new(workflow: :print, step: "files", reason: Graph::Prints.unreadable_line(path, reason), next_command: "plastic sync down --overwrite #{path}", because: "sync up cannot read the file, and its rows print it again")
      end
    end
  end
end
