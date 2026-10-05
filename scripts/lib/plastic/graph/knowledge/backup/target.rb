# frozen_string_literal: true

require_relative "../backup"
require_relative "folders"

module Plastic
  module Graph
    module Knowledge
      class Backup
        # The store a backup call works on: its slug, its directory, the home
        # database that holds the rows, and the session that owns the writes.
        Target = Data.define(:home_db, :root, :slug, :session) do
          def folders = Folders.new(root)

          def file(name) = File.join(root, "#{name}.db")
        end
      end
    end
  end
end
