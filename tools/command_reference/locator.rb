# frozen_string_literal: true

module CommandReference
  # Finds the line of the statement that declares a gate, a step, a read or an outcome.
  class Locator
    REACH = 8

    def initialize(source)
      @source = source
    end

    def above(file, line, word)
      lines = @source.lines(file)
      hit = Locator.window(line).lazy.map { |number| [number, Locator.judge(lines[number - 1], word)] }.find(&:last)
      hit.first if hit&.last == :found
    end

    def named(files, word, name) = search(files, /^\s*#{word}[ (]+[:"]#{Regexp.escape(name.to_s)}\b/)

    def first(files, word) = search(files, /^\s*#{word}\b/)

    def search(files, pattern)
      files.each { |file| (line = @source.find_line(file, pattern)) and return [file, line] }
      nil
    end

    def at(callable, word)
      file, line = callable&.source_location
      return unless file

      path = @source.relative(file)
      found = above(path, line, word)
      [path, found] if found
    end

    def self.window(line) = line.downto([line - REACH, 1].max)

    def self.judge(text, word)
      return :found if text.match?(/\b#{word}\b/)

      :stop if text.match?(/^\s*def |^\s*$/)
    end
  end
end
