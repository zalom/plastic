# frozen_string_literal: true

module Plastic
  module Graph
    module Knowledge
      # The form a Verification line must take to count: a word that does not deny it, the parts of its label filled in.
      module OutcomeForm
        NEGATIVE = %r{\A(?:\z|(?:no|not|none|pending|n/a|tbd|false|rejected|awaiting|waiting|requested|changes|declined|denied|never|unapproved)[[:punct:]]*(?:\s|\z))}i
        # The marks a person writes before a word in Markdown or plain text, and the spaces between them, read past before the first word is judged.
        MARKS = /\A[\s\x60"'(\[{_~“‘«<>\\\-–—]+/
        DELIVERED_PATH = %r{\A\x60?(resources/output/[^\s\x60]+)\x60?}
        FORMS = {
          "Merged" => /\A(?:\S+ +into +)?\S+ +at +(?:\D*\d|\x60?\h{7,40}\b)/,
          "Committed" => /\A\S+ +at +\x60?\h{7,40}\x60?(?![\w#])/,
          "Delivered" => /#{DELIVERED_PATH} +because +\S/,
          "Approved" => /\A(?:by +)?\S.*? +on +\d{4}-\d{2}-\d{2}(?!\d)/
        }.freeze
        SHOWN = {
          "Merged" => "Merged: <branch> into <base> at <commit or pull request>",
          "Committed" => "Committed: <branch> at <commit>",
          "Delivered" => "Delivered: resources/output/<path> because <reason>",
          "Approved" => "Approved: <person> on <YYYY-MM-DD>"
        }.freeze
        PLACEHOLDER = /<(?:branch|base|commit or pull request|commit|path|reason|person|YYYY-MM-DD)>/

        def self.in_form?(label, value) = !NEGATIVE.match?(value.sub(MARKS, "")) && FORMS.fetch(label).match?(value) && !PLACEHOLDER.match?(value)

        def self.shown(label) = SHOWN.fetch(label)

        # The path a Delivered line names, read without its code marks.
        def self.delivered_path(value) = value[DELIVERED_PATH, 1]
      end
    end
  end
end
