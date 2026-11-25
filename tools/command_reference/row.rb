# frozen_string_literal: true

module CommandReference
  # A gate or a step of a code workflow, with the line that declares it.
  Row = Data.define(:kind, :name, :check, :stops, :say, :file, :line) do
    def draft = { lane: (kind == :agent) ? :agent : :code, text: Words.sentence(name), say:, stops: [] }

    def location = "#{File.basename(file)}:#{line}"

    def gate? = kind == :gate

    def saying = ["The agent step \"#{Words.plain(name)}\" prints:", "", "> #{Words.placeholders(say).gsub("\n", "\n> ")}", ""]

    def check_cell = Array(check).map { |text| "`#{Words.cell(text)}`" }.join

    def gate_ending(step) = Ending.new(:gate, (step.stops == :refusal) ? 3 : 1, step.offers || Endings::NONE, name, file, line)
  end
end
