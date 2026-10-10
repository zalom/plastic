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
      line.downto([line - REACH, 1].max).each do |number|
        text = lines[number - 1]
        return number if text.match?(/\b#{word}\b/)
        return nil if text.match?(/^\s*def |^\s*$/)
      end
      nil
    end

    def named(files, word, name)
      pattern = /^\s*#{word}[ (]+[:"]#{Regexp.escape(name.to_s)}\b/
      files.each { |file| (line = @source.find_line(file, pattern)) and return [file, line] }
      nil
    end

    def first(files, word)
      files.each { |file| (line = @source.find_line(file, /^\s*#{word}\b/)) and return [file, line] }
      nil
    end

    def at(callable, word)
      file, line = callable&.source_location
      return unless file

      found = above(@source.relative(file), line, word)
      [@source.relative(file), found] if found
    end
  end
end
