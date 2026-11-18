# frozen_string_literal: true

require_relative "../cli/hook"
require_relative "chat_record"

module Plastic
  module Hooks
    # UserPromptSubmit: records the prompt in the chat history of the machine and prints nothing, so the model's
    # context stays as it was.
    class Prompt < CLI::Hook
      changes(local: "The prompt is added to the chat history in plastic.db")

      def respond(event)
        return say("the event names no session") unless session_id
        text = event[:prompt]
        return say("the event carries no prompt") unless text

        ChatRecord.new(scope:, session_id:, environment:).call(role: "user", text:)
        nil
      end

      private

      def say(reason)
        environment.err.puts "plastic hook: #{reason}; nothing recorded"
        nil
      end
    end
  end
end
