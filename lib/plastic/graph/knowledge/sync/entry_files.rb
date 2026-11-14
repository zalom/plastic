# frozen_string_literal: true

require "json"
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
            (sha && Entry.generated?(path) && same_print?(path, print)) ? print.sha256 : sha
          end

          def same_print?(path, print) = print.sha256 && same_content?(@folder.read(path), print.text)

          def same_content?(bytes, text)
            JSON.parse(bytes.force_encoding(Encoding::UTF_8)) == JSON.parse(text)
          rescue JSON::ParserError
            false
          end
        end
      end
    end
  end
end
