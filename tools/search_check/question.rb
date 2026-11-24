# frozen_string_literal: true

module SearchCheck
  # One known question: what to type and which intents hold the answer.
  Question = Data.define(:id, :question, :keywords, :answers) do
    def self.from(row) = new(row.fetch("id"), row.fetch("question"), row.fetch("keywords", ""), row.fetch("answers"))

    def line(rank) = format("%-6s %-14s %s", id, rank ? "hit  rank #{rank}" : "miss", question)
  end
end
