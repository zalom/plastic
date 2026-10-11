# frozen_string_literal: true

module CommandReference
  # The endings one source file spells out: raised errors, next: lines and stop decisions.
  class FileEndings
    RAISES = { "Usage" => [2, "Usage error"], "Refusal" => [3, "Refused"], "Failure" => [1, "Failed"] }.freeze
    RAISE_LINE = /\braise (?:CLI::)?(?:Command::)?(Usage|Refusal|Failure)\b(?:, "(.*)")?/
    NEXT_LINE = /\bnext_step\((?:"([^"]+)"|[^,)]+)/
    OFFERS = "Offers the next command"
    INTERPOLATION = /\#\{([^}]*)\}/

    def self.name_of(code) = code[/[a-z_]\w*/] || "value"

    def self.placeholder(literal)
      literal.gsub(/((?<=\S))?#{INTERPOLATION}/o) do
        glued, code = Regexp.last_match.captures
        name = name_of(code).upcase
        glued ? " [#{name}]" : name
      end
    end

    def self.message(kind, literal)
      literal ? "#{kind}: #{literal.gsub(INTERPOLATION) { "%{#{name_of(Regexp.last_match(1))}}" }}" : kind
    end

    def initialize(source, file, only: nil)
      @file = file
      @only = only
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
        next if @only && !@only.include?(number)

        code, kind = RAISES.fetch(match[1])
        Ending.new(:raise, code, Endings::NONE, self.class.message(kind, match[2]), @file, number)
      end
    end

    def next_steps
      found do |text, number|
        match = text.match(NEXT_LINE) or next
        literal = match[1]
        Ending.new(:next_step, 0, literal ? self.class.placeholder(literal) : Endings::RUNTIME, OFFERS, @file, number)
      end
    end

    def found(&) = @lines.each_with_index.filter_map { |text, index| yield(text, index + 1) }
  end
end
