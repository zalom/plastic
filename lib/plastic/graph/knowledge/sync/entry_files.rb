# frozen_string_literal: true

require_relative "entry"

module Plastic
  module Graph
    module Knowledge
      class Sync
        # Builds the entries of a store folder from its files. A generated file that holds the
        # content of its print in other bytes is level: the bytes are a formatter's, not a person's edit.
        class EntryFiles
          def initialize(folder)
            @folder = folder
          end

          def entry(path, printed_sha, print) = Entry.new(path, level_sha(path, print), printed_sha, print)

          private

          def level_sha(path, print)
            sha = @folder.digest(path)
            (sha && Entry.generated?(path) && print.same_json?(@folder)) ? print.sha256 : sha
          end
        end
      end
    end
  end
end
