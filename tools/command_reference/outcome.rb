# frozen_string_literal: true

module CommandReference
  # One outcome line of a workflow.
  Outcome = Data.define(:name, :check, :fallback, :offers, :because, :to, :exit_code, :file, :line) do
    def ends? = to == :noop

    def exit_words = (name == :handoff) ? "hands off, exit #{exit_code}" : "finishes, exit 0"

    def next_words = Array(offers).map { |each| "next: #{each}" }.first || Endings::NONE

    def ending(kind) = Ending.new(kind, exit_code, offers || Endings::NONE, because, file, line)
  end
end
