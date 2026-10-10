# frozen_string_literal: true

module CommandReference
  # Words cut into lines of a given width, and short names.
  module Words
    def self.wrap(words, width)
      words.to_s.split.reduce([]) { |all, word| join(all, word, width) }.then { |lines| lines.empty? ? [+""] : lines }
    end

    def self.join(all, word, width)
      *head, last = all
      (last && last.size + word.size + 1 <= width) ? [*head, "#{last} #{word}"] : [*all, word]
    end

    def self.cell(text) = text.to_s.gsub("|", "\\\\|")

    def self.short(klass) = klass.name.split("::").last
  end
end
