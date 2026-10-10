# frozen_string_literal: true

module CommandReference
  # Words cut into lines of a given width, and short names.
  module Words
    def self.wrap(words, width)
      words.to_s.split.each_with_object([+""]) do |word, lines|
        lines << +"" if !lines.last.empty? && lines.last.size + word.size + 1 > width
        lines.last << " " unless lines.last.empty?
        lines.last << word
      end
    end

    def self.short(klass) = klass.name.split("::").last
  end
end
