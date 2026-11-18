# frozen_string_literal: true

require_relative "../../routine"

module Plastic
  module Commands
    module Chat
      # Lists the messages the hooks recorded in the machine's chat history, every store together
      # in time order. It reads the home's database and writes nothing.
      class List < Routine
        opens_no_store

        option :since, switch: "--since DATE", text: "list the messages from this day on, as YYYY-MM-DD in the clock's zone; all of them when left out"

        workflow :code_list_chat, next: :noop
      end
    end
  end
end
