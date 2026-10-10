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

    def comment_above(file, line)
      found = []
      index = line - 2
      while index >= 0 && (text = lines(file)[index].strip).start_with?("#")
        found.unshift(text.sub(/\A# ?/, ""))
        index -= 1
      end
      found.reject { |text| text.start_with?("frozen_string_literal") }
    end

    def lambda_code(callable)
      return unless callable

      file, line = callable.source_location
      text = lines(relative(file))[(line - 1)..].join("\n")
      return method_text(text) if callable.is_a?(Method)

      brace_body(text, text.index("{", text.index("->")))
    end

    def blocks(comment)
      groups = comment.slice_when { |a, b| a.empty? || b.empty? || a.start_with?("  ") != b.start_with?("  ") }
      groups.reject { |group| group.all?(&:empty?) }.map { |group| block(group) }
    end

    def find_line(file, pattern) = lines(file).index { |text| text.match?(pattern) }&.+(1)

    def method_lines(file, line)
      body = lines(file)[(line - 1)..]
      indent = body.first[/\A */]
      return [body.first.strip] if body.first.match?(/def \S+( |\(.*\) )= /)

      body[0..body.index { |text| text == "#{indent}end" }].map { |text| text.delete_prefix(indent) }
    end

    private

    def absolute(file) = file.start_with?("/") ? file : File.join(@root, file)

    def block(group)
      return [:text, group.join(" ")] unless group.first.start_with?("  ")

      [:code, group.map { |text| text.delete_prefix("  ") }.join("\n")]
    end

    def brace_body(text, open)
      depth = 0
      close = (open...text.size).find do |index|
        depth += { "{" => 1, "}" => -1 }.fetch(text[index], 0)
        depth.zero?
      end
      text[(open + 1)...close].strip.gsub(/\s+/, " ")
    end

    def method_text(text)
      first = text.lines.first.strip
      return first.sub(/\Adef \S+( |\(.*\) )= /, "") if first.match?(/\Adef \S+( |\(.*\) )= /)

      rows = text.lines
      rows[0..rows.index { |row| row.match?(/\A\s*end\b/) }].map(&:strip).join(" ")
    end
  end
end
