# frozen_string_literal: true

module CommandReference
  class Touches
    # One method of a graph class and the text it runs: the method itself, the
    # methods of the same file it calls and the constants they use. No method,
    # or a method the file does not define, reads as the whole file.
    class Target
      CALL = /\b([a-z_]\w*[?!]?)/
      CONSTANT = /\b([A-Z][A-Z0-9_]*)\b/

      attr_reader :file, :component

      def initialize(source, file, method, component)
        @source = source
        @file = file
        @method = method
        @component = component
      end

      def part = (Part.new(component, file) if component)

      def key = [file, @method.to_s]

      def text = (@text ||= closure.empty? ? whole : [closure, constants].join("\n"))

      private

      def whole = @source.lines(@file).join("\n")

      def closure
        @closure ||= @method ? names.filter_map { |name| body(name) }.join("\n") : ""
      end

      def constants
        reader = ConstantText.new(@source, @file)
        closure.scan(CONSTANT).flatten.uniq.filter_map { |name| reader.of(name) }.join("\n")
      end

      def names
        queue = [@method.to_s]
        queue.each { |name| queue.concat(calls(name) - queue) }
        queue
      end

      def calls(name)
        text = body(name)
        text ? text.scan(CALL).flatten.select { |word| defined_here?(word) } : []
      end

      def body(name)
        line = @source.find_line(@file, /^\s*def #{Regexp.escape(name)}\b/)
        @source.method_lines(@file, line).join("\n") if line
      end

      def defined_here?(word) = @source.find_line(@file, /^\s*def #{Regexp.escape(word)}\b/)
    end
  end
end
