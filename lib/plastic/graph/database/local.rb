# frozen_string_literal: true

module Plastic
  module Graph
    class Database
      # The local database, for what belongs to one machine. A home that still
      # holds local.db and no plastic.db is behind: the install and the update
      # move it, and nothing on open renames or creates a file.
      class Local < Database
        FORMER = "local.db"

        def initialize(home)
          super(File.join(home, Schema.file(:local)), Schema.fetch(:local), key: :local)
          @former = File.join(home, FORMER)
        end

        private

        def open_file
          raise Behind, "#{FORMER} is not migrated to #{file}; run plastic update" if File.exist?(@former) && !File.exist?(path)

          super
        end
      end
    end
  end
end
