# frozen_string_literal: true

module CommandReference
  # Text taken from the kernel's own files: comments and lambda bodies.
  class Source
    def initialize(root)
      @root = root
      @files = {}
    end

    def lines(file) = (@files[file] ||= File.readlines(absolute(file), chomp: true))

    def relative(file) = file.delete_prefix("#{@root}/")

    def class_comment(klass)
      file, line = Object.const_source_location(klass.name)
      comment_above(relative(file), line)
    end

    def comment_above(file, line) = Snippet.comment(lines(file).first(line - 1))

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

    def absolute(file) = file.start_with?("/") ? file : File.join(@root, file)
  end
end
