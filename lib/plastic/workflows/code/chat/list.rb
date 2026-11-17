# frozen_string_literal: true

require "date"
require_relative "../../../code_workflow"
require_relative "../../../graph/database"
require_relative "../../../graph/work/chat/reader"

module Plastic
  module Workflows
    module Code
      module Chat
        # Prints the chat history of the machine in time order, one row for each message, and names
        # each store whose folder is gone. It writes nothing.
        class List < CodeWorkflow
          NONE = "no prompts"

          clear_declarations

          sets :messages

          read "read the messages" do |context|
            since = start_of(context.since, context.now)
            home = Plastic::Graph::Database.open_local(context.scope.plastic_home).fetch(:local)
            context[:messages] = Plastic::Graph::Work::Chat::Reader.new(home).messages(since:)
          end

          read "name each store with no folder" do |context|
            home = context.scope.plastic_home
            stores = context.messages.filter_map { |message| message["store"] }.uniq
            stores.reject { |store| File.directory?(File.join(home, "stores", store)) }.each { |store| context.print("store #{store} has no store folder; its messages are listed") }
          end

          read "print each message" do |context|
            context.print(NONE) if context.messages.empty?
            context.messages.each { |message| context.row(message["role"], line(message)) }
          end

          outcome :done, offers: nil, because: "the chat history is listed"

          def self.line(message)
            [message["at"], message["store"] || "-", message["intent_id"] || "-", message["text"]].join("  ")
          end

          def self.start_of(text, now)
            return unless text

            day = Date.iso8601(text)
            Time.new(day.year, day.month, day.day, 0, 0, 0, now.utc_offset)
          rescue Date::Error
            raise Usage, "--since takes a day as YYYY-MM-DD, not #{text.inspect}"
          end
        end
      end
    end
  end
end
