# frozen_string_literal: true

module CommandReference
  # One workflow of a command's chain.
  Flow = Data.define(:key, :klass, :lane, :file, :line, :comment, :facts, :rows, :outcomes) do
    def agent? = lane == "agent"

    def short = Words.short(klass)

    def location = "#{File.basename(file)}:#{line}"

    def closing = outcomes.find(&:ends?)

    def captions = ["#{lane.upcase} WORKFLOW", short, ":#{key}"]

    def closing_words = agent? ? "hands off, exit #{closing.exit_code}" : "finishes, exit 0"

    def files = rows.filter_map(&:file) + [file]

    def raising? = lane == "code" && klass.steps.any? { |step| !step.is_a?(Plastic::CodeWorkflow::Gate) }

    def endings = gate_endings + outcomes.select(&:ends?).map { |outcome| outcome.ending(closing_kind(outcome)) }

    def closing_kind(outcome) = (agent? && outcome.name == :handoff) ? :handoff : :outcome

    def gate_endings = klass.steps.zip(rows).filter_map { |step, row| row.gate_ending(step) if step.is_a?(Plastic::CodeWorkflow::Gate) }
  end
end
