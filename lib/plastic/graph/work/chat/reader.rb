# frozen_string_literal: true

require_relative "../../../clock"

module Plastic
  module Graph
    module Work
      module Chat
        # The read side of the home's `chat_messages` table: the messages of every store in time
        # order, from one time on when `since` is given. It reads the home's one database, not a store's.
        class Reader
          ASKED = <<~SQL
            SELECT 1 FROM chat_messages WHERE role = 'user' AND (store = :store OR session_id = :session)
              AND instr(lower(text), lower(:words)) > 0 LIMIT 1
          SQL

          def initialize(home)
            @home = home
          end

          # Whether an owner message of the store `store` or of the session `session` holds `words`, in any case.
          # A message of an intent of the store is a message of the store.
          def asked?(words, store:, session:)
            return false if words.to_s.strip.empty?

            !@home.rows(ASKED, words: words.strip, store:, session: session.to_s).empty?
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
