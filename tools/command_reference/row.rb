# frozen_string_literal: true

module CommandReference
  ROW_KINDS = { read: "read", gate: "gate", step: "step", agent: "agent step" }.freeze

  # A gate or a step of a code workflow, with the line that declares it.
  Row = Data.define(:kind, :name, :check, :stops, :say, :file, :line) do
    def location = "#{File.basename(file)}:#{line}"

    def gate? = kind == :gate

    def headline = gate? ? "passes when #{check}" : name

    def reason = gate? ? name : "the step ran and its done check still fails"

    def kind_words = "#{ROW_KINDS.fetch(kind)}#{stops_words}"

    def stops_words = if gate?
                        ", stops with exit #{(stops == :refusal) ? 3 : 1}"
                      else
                        ""
                      end

    def saying = ["The agent step \"#{name}\" prints:", "", "> #{say.gsub("\n", "\n> ")}", ""]

    def check_cell = Array(check).map { |text| "`#{Words.cell(text)}`" }.join

    def gate_ending(step) = Ending.new(:gate, (step.stops == :refusal) ? 3 : 1, step.offers || Endings::NONE, name, file, line)
  end
end
