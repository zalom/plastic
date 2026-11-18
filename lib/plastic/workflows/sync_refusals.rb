# frozen_string_literal: true

module Plastic
  module Workflows
    # The refusals of a sync that finds a record changed on both sides, in the words of each direction.
    module SyncRefusals
      # What each option keeps, in the words of the direction. The paths come last, so the last word of a refusal is a path.
      OVERWRITE_WORDS = {
        up: "--overwrite PATH reads that file into rows, --overwrite reads every file",
        down: "--overwrite PATH prints that record's rows over the file, --overwrite prints every record"
      }.freeze
      REFUSED_BEFORE = OVERWRITE_WORDS.transform_values do |words|
        "changed on both sides since the last print, nothing written. #{words}, " \
          "--merge applies the one-sided changes and lists the rest. The records: %{conflicts}"
      end.freeze
      REFUSED_AFTER = OVERWRITE_WORDS.transform_values do |words|
        "changed on both sides since the last print, left as they are. #{words}. The records: %{conflicts}"
      end.freeze
    end
  end
end
