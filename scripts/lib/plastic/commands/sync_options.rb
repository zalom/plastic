# frozen_string_literal: true

module Plastic
  module Commands
    # The switches both sync directions take.
    module SyncOptions
      def self.extended(command)
        command.option :overwrite, switch: "--overwrite [PATH]", default: false,
          text: "settle conflicts on this side: one record by its path, or every record with no path"
        command.option :merge, switch: "--merge", default: false,
          text: "apply the one-sided changes, then list the conflicts"
        command.writes :work, :knowledge, :references
      end
    end
  end
end
