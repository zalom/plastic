# frozen_string_literal: true

module CommandReference
  # The lines of one file that run when a call starts from the given methods: the
  # methods themselves and every method of the listed files they name.
  class CallClosure
    WORD = /\b([a-z_]\w*[?!]?)/

    def initialize(source, files, roots)
      @source = source
      @files = files
      @roots = roots
    end

    def lines(file) = bodies.select { |home, _| home == file }.flat_map { |_, range| range.to_a }.to_set

    private

    def bodies
      @bodies ||= names.flat_map { |name| @files.filter_map { |file| body(file, name) } }
    end

    def names
      queue = @roots.dup
      queue.each { |name| queue.concat(called(name) - queue) }
      queue
    end

    def called(name) = @files.filter_map { |file| text(file, name) }.flat_map { |code| code.scan(WORD).flatten.select { |word| known?(word) } }

    def text(file, name) = (line = @source.find_line(file, definition(name))) && @source.method_lines(file, line).join("\n")

    def body(file, name)
      line = @source.find_line(file, definition(name))
      [file, line..(line + @source.method_lines(file, line).size - 1)] if line
    end

    def known?(word) = @files.any? { |file| @source.find_line(file, definition(word)) }

    def definition(name) = /^\s*def #{Regexp.escape(name)}\b/
  end
end
