# frozen_string_literal: true

module Plastic
  class CLI
    # The switches both sync directions take, each with the words of its direction.
    module SyncOptions
      OVERWRITE_TEXT = {
        up: "read the file of the path into rows, or every file with no path",
        down: "print the rows of the path over its file, or every record with no path"
      }.freeze

      def self.add(command, direction)
        command.option :overwrite, switch: "--overwrite [PATH]", default: false, text: OVERWRITE_TEXT.fetch(direction)
        command.option :merge, switch: "--merge", default: false,
          text: "apply the one-sided changes, then list the conflicts"
        command.writes :work, :knowledge, :retrieval
      end

      # The switches of sync up.
      module Up
        def self.extended(command) = SyncOptions.add(command, :up)
      end

      # The switches of sync down.
      module Down
        def self.extended(command) = SyncOptions.add(command, :down)
      end
    end
  end
end
