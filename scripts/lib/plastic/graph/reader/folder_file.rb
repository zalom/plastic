# frozen_string_literal: true

module Plastic
  module Graph
    class Reader
      # One file of the store folder: its path, its path inside its intent
      # folder, and its bytes and modification time on disk.
      FolderFile = Data.define(:folder, :path, :rel) do
        def bytes = folder.read(path)

        def mtime = File.mtime(folder.path(path)).to_i
      end
    end
  end
end
