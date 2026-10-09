# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Opens an intent: writes its row and its first rows, and prints its
    # folder and store/index.json in the same call.
    class IntentNew < Routine
      subject :title
      argument :title, label: "TITLE", text: "what the intent is for, in words", rest: true
      option :parent_id, switch: "--parent ID", text: "the intent this one is a child of"
      option :ref, switch: "--ref REF", text: "a ticket, a link, or another intent as ID-ORIGIN"
      option :after, switch: "--after ID", text: "an intent this one grows out of, linked as source"
      option :kind, switch: "--kind KIND", text: "the kind of work", default: "work"
      option :status, switch: "--status STATUS", text: "open, active, parked or future", default: "open"
      writes :work, :knowledge, :references

      workflow :code_write_intent, next: :noop
    end
  end
end
