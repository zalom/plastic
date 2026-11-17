# frozen_string_literal: true

module Plastic
  module Graph
    # The store backups: the writer that takes one, the folders that hold
    # them, the restorer that brings one back and the purger that removes the
    # old ones. The folders on disk decide which backups exist.
    module Backup
    end
  end
end

require_relative "backup/folders"
