# frozen_string_literal: true

require_relative "../../../clock"

module Plastic
  module Graph
    module Work
      module Chat
        # The read side of the home's `chat_messages` table: the messages of every store in time
        # order, from one time on when `since` is given. It reads the home's one database, not a store's.
        class Reader
          def initialize(home)
            @home = home
          end

          def messages(since: nil)
            return @home.rows("SELECT * FROM chat_messages ORDER BY julianday(at), id") unless since

            @home.rows("SELECT * FROM chat_messages WHERE julianday(at) >= julianday(:since) ORDER BY julianday(at), id", since: Plastic.timestamp(since))
          end
        end
      end
    end
  end
end
