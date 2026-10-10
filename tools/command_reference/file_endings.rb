# frozen_string_literal: true

module CommandReference
  # The endings one source file spells out: raised errors, next: lines and stop decisions.
  class FileEndings
    RAISES = { "Usage" => 2, "Refusal" => 3, "Failure" => 1 }.freeze
    RAISE_LINE = /\braise (?:CLI::)?(?:Command::)?(Usage|Refusal|Failure)\b/
    NEXT_LINE = /\bnext_step\((?:"([^"]+)"|[^,)]+)/

    def initialize(source, file)
      @file = file
      @lines = source.lines(file)
    end

    def call = raises + next_steps

    def decisions
      found { |text, number| Ending.new(:decision, 0, Endings::NONE, "blocks the stop", @file, number) if text.include?('"decision"') }
    end

    private

    def raises
      found do |text, number|
        match = RAISE_LINE.match(text) or next
        Ending.new(:raise, RAISES.fetch(match[1]), Endings::NONE, text.strip, @file, number)
      end
    end

    def next_steps
      found do |text, number|
        match = text.match(NEXT_LINE) or next
        Ending.new(:next_step, 0, match[1] || Endings::RUNTIME, text.strip, @file, number)
      end
    end

    def found(&) = @lines.each_with_index.filter_map { |text, index| yield(text, index + 1) }
  end
end
