# frozen_string_literal: true

require_relative "../backup"
require_relative "folders"

module Plastic
  module Graph
    module Backup
      # The root directory of one store and its slug, which name where its backups live and how a backup row calls them.
      Site = Data.define(:root, :slug) do
        def folders = Folders.new(root)

        def row(folder, at) = { name: "#{slug}/#{folder}", **folders.summary(folder), at: }
      end
    end
  end
end
