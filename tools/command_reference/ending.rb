# frozen_string_literal: true

module CommandReference
  # One way a command call ends.
  Ending = Data.define(:kind, :exit_code, :next_text, :text, :file, :line) do
    def stop = Stop.new({ 0 => :end, 3 => :refusal }.fetch(exit_code, :failure), exit_code, Words.sentence(text), next_line)

    def next_line = [Endings::NONE, Endings::RUNTIME].include?(next_text) ? nil : "next: #{Words.angled(next_text)}"
  end
end
