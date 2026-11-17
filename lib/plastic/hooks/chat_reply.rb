# frozen_string_literal: true

module Plastic
  module Hooks
    # Records the reply a Stop event carries, when the chat_sync setting is full. The default, user_only, records none.
    class ChatReply
      def initialize(config, record)
        @config = config
        @record = record
      end

      def call(event)
        text = event[:last_assistant_message]
        @record.call(role: "assistant", text:) if text && full?
      end

      private

      def full? = @config.choice(["chat_sync"], default: "user_only", allowed: %w[user_only full]) == "full"
    end
  end
end
