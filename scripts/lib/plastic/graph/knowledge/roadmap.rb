# frozen_string_literal: true

require_relative "../record"

module Plastic
  module Graph
    module Knowledge
      # A roadmap: a named plan, held as rows instead of a hand-kept file.
      Roadmap = Data.define(:slug, :title, :goal, :opened_at, :updated_at, :origin_id) do
        include Record
      end

      # A batch's or an item's own words, carried as one value so a method
      # that builds a row takes one argument for them, not three.
      Roadmap::Fields = Data.define(:title, :goal, :done) do
        # These words over a row already written: a field left out keeps the
        # row's word for it, and a title missing from both takes `fallback`.
        def over(row, fallback)
          given = Array(done)
          with(title: title || row&.title || fallback, goal: goal || row&.goal, done: given.empty? ? row&.done_lines.to_a : given)
        end
      end

      # One wave of a roadmap: a titled group of items with its own goal and
      # done criteria, one per line.
      Roadmap::Batch = Data.define(:roadmap, :position, :title, :goal, :done, :updated_at, :origin_id) do
        include Record

        def done_lines = done.to_s.lines(chomp: true)
      end

      # One planned piece of work inside a batch. `mark` is the owner's call
      # when an item is dropped; `intent_id` is set once the item is started.
      Roadmap::Item = Data.define(:roadmap, :item, :batch, :position, :title, :goal, :done, :intent_id,
        :mark, :updated_at, :origin_id) do
        include Record

        def done_lines = done.to_s.lines(chomp: true)

        def dropped? = mark == "dropped"

        def start_refusal(state)
          return "item #{item} already has an intent" if intent_id

          "item #{item} is #{state}, not ready" unless state == "ready"
        end

        def spec_body(batches)
          owner = batches.find { |row| row.position == batch }
          criteria = (owner.done_lines + done_lines).map { |line| "- [ ] #{line}" }
          ["## Goal", "", *[owner.goal, goal].compact, "", "## Done criteria", "", *criteria, ""].join("\n")
        end
      end

      # An edge between two items of the same roadmap: `to` waits for `from`.
      Roadmap::Edge = Data.define(:roadmap, :from, :to, :kind, :origin_id) do
        include Record
      end

      # One line of a roadmap's log: a dated note about the roadmap itself.
      Roadmap::LogLine = Data.define(:roadmap, :position, :at, :text, :session_id, :origin_id) do
        include Record
      end
    end
  end
end
