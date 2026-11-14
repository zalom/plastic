# frozen_string_literal: true

require_relative "../../prints"
require_relative "../store_folder"

module Plastic
  module Graph
    module Knowledge
      class Sync
        # How the file of an entry differs from its rows and from its last print.
        module Changes
          # The file already holds what the rows print.
          def level? = [file_sha].compact.include?(rows_sha)

          def file_changed? = file_sha && file_sha != printed_sha

          # A person changed a file since its last print, or one never printed: the file holds
          # neither the rows' print nor the recorded one. A graph file against bare rows is not an edit.
          def hand_edited? = !level? && file_changed? && !bare_graph?

          def rows_changed? = rows_sha && rows_sha != printed_sha && !bare_graph?

          def bare_graph? = !printed_sha && StoreFolder.graph_file?(path) && rows_sha == Prints.empty_graph_sha(path)

          def conflict? = !level? && file_changed? && rows_changed?
        end
      end
    end
  end
end
