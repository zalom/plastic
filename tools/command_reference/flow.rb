# frozen_string_literal: true

module CommandReference
  # One workflow of a command's chain.
  Flow = Data.define(:key, :klass, :lane, :file, :line, :facts, :rows, :outcomes) do
    def agent? = lane == "agent"

    def pairs(items) = items.map { |item| [self, item] }

    def short = Words.short(klass)

    def path = Words.path(klass)

    def anchor = Words.anchor(path)

    def location = "#{File.basename(file)}:#{line}"

    def closing = outcomes.find(&:ends?)

    def captions = ["#{lane.upcase} WORKFLOW", short, ":#{key}"]

    def files = rows.filter_map(&:file) + [file]

    def raising? = lane == "code" && klass.steps.any? { |step| !step.is_a?(Plastic::CodeWorkflow::Gate) }

    def endings = gate_endings + outcomes.select(&:ends?).map { |outcome| outcome.ending(closing_kind(outcome)) }

    def closing_kind(outcome) = (agent? && outcome.name == :handoff) ? :handoff : :outcome

    def step_changes = klass.steps.grep(Plastic::CodeWorkflow::Step).flat_map { |step| step.changes.to_a }

    def gate_endings = klass.steps.zip(rows).filter_map { |step, row| row.gate_ending(step) if step.is_a?(Plastic::CodeWorkflow::Gate) }
  end
end
