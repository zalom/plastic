# frozen_string_literal: true

module CommandReference
  # Text taken from the kernel's own files: lambda bodies and method bodies.
  class Source
    attr_reader :root

    def initialize(root)
      @root = root
      @files = {}
    end

    def lines(file) = (@files[file] ||= File.readlines(absolute(file), chomp: true))

    def relative(file) = file.delete_prefix("#{@root}/")

    def lambda_code(callable)
      return unless callable

      file, line = callable.source_location
      text = lines(relative(file))[(line - 1)..].join("\n")
      return Snippet.method_text(text) if callable.is_a?(Method)

      Snippet.brace_body(text, text.index("{", text.index("->")))
    end

    def find_line(file, pattern) = lines(file).index { |text| text.match?(pattern) }&.+(1)

    def method_lines(file, line) = Snippet.method_lines(lines(file)[(line - 1)..])

    private

    def absolute(file) = File.join(@root, file)
  end
end
