# frozen_string_literal: true

require_relative "former_name"

module Plastic
  module Graph
    class Database
      # The local database, for what belongs to one machine. A home.db left
      # from before becomes local.db on the first use, and this database
      # then says so once.
      class Local < Database
        def initialize(home)
          super(File.join(home, Schema.file(:local)), Schema.fetch(:local))
          @former = FormerName.new(File.join(home, "home.db"))
        end

        def phrases = [@former.said, *super].compact

        private

        def connection
          @former.move_to(path)
          super
        end
      end
    end
  end
end
