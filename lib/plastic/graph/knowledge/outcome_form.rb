# frozen_string_literal: true

module Plastic
  module Graph
    module Knowledge
      # The form a Verification line must take to count: a word that does not deny it, the parts of its label filled in.
      module OutcomeForm
        NEGATIVE = %r{\A(?:\z|(?:no|not|none|pending|n/a|tbd|false|rejected|awaiting|waiting|requested|changes|declined|denied|never|unapproved)[[:punct:]]*(?:\s|\z))}i
        # The marks a person writes before a word in Markdown or plain text, and the spaces between them, read past before the first word is judged.
        MARKS = /\A[\s\x60"'(\[{_~“‘«<>\\\-–—]+/
        FORMS = {
          "Merged" => /\A(?:\S+ +into +)?\S+ +at +(?:\D*\d|\x60?\h{7,40}\b)/,
          "Committed" => /\A\S+ +at +\x60?\h{7,40}\x60?(?![\w#])/,
          "Delivered" => %r{\A\x60?(resources/output/[^\s\x60]+)\x60? +because +\S},
          "Approved" => /\A(?:by +)?\S.*? +on +\d{4}-\d{2}-\d{2}(?!\d)/,
          "Abandoned" => /\A(?:superseded +by +intent +\d+\b|dropped +because +\S)/i
        }.freeze
        SHOWN = {
          "Merged" => "Merged: <branch> into <base> at <commit or pull request>",
          "Committed" => "Committed: <branch> at <commit>",
          "Delivered" => "Delivered: resources/output/<path> because <reason>",
          "Approved" => "Approved: <person> on <YYYY-MM-DD>",
          "Abandoned" => ["Abandoned: superseded by intent <id>", "Abandoned: dropped because <reason>"]
        }.freeze
        PLACEHOLDER = /<(?:branch|base|commit or pull request|commit|path|reason|person|YYYY-MM-DD|id)>/

        def self.in_form?(label, value) = !NEGATIVE.match?(value.sub(MARKS, "")) && FORMS.fetch(label).match?(value) && !PLACEHOLDER.match?(value)

        def self.shown(label) = Array(SHOWN.fetch(label)).first

        def self.formed?(label) = FORMS.key?(label)

        # Every form of the line, quoted and joined by or.
        def self.shown_forms(label) = Array(SHOWN.fetch(label)).map { |form| "'#{form}'" }.join(" or ")

        # The text of a note that writes the line, the form without its label.
        def self.note_text(label) = shown(label).delete_prefix("#{label}: ")

        # The path a Delivered line in its form names, read without its code marks, else nil.
        def self.delivered_path(value) = value[FORMS.fetch("Delivered"), 1]
      end
    end
  end
end
