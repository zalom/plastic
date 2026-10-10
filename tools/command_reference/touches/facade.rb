# frozen_string_literal: true

module CommandReference
  class Touches
    # Finds what a call on the work graph or the retrieval graph runs: the
    # delegation line, the class behind it, and the method there. From a
    # method it also finds what that method hands the work to.
    class Facade
      GRAPH = "scripts/lib/plastic/graph"
      FILES = { work: "#{GRAPH}/work_graph.rb", retrieval: "#{GRAPH}/retrieval_graph.rb" }.freeze
      WRITERS = "#{GRAPH}/work/writers.rb"
      CONSTANT = Accessors::CONSTANT
      BUILT = /#{CONSTANT}(?:\([^)]*\))?(?:\.(\w+[?!]?))?/

      def initialize(source, root)
        @source = source
        @root = root
        @delegations = {}
        @accessors = Accessors.new(source, FILES.values)
      end

      def targets(side, method, hop = nil)
        file = FILES.fetch(side)
        found = delegated(file, method) || direct(file, method) || included(side, method) || []
        hop ? hopped(found, hop) : found
      end

      def follow(target)
        text = target.text
        [*writers_of(text, target.file), *(accessed(text) unless target.component), *built(text)]
      end

      def constant_file(klass)
        tail = klass.split("::").last(2).map { |part| Plastic.snake(part) }.join("/")
        Dir.glob("#{@root}/#{GRAPH}/**/#{tail}.rb").map { |path| @source.relative(path) }.min
      end

      private

      def delegated(file, method)
        accessor, real = (@delegations[file] ||= Delegations.new(@source, file).table)[method]
        accessor && class_target(accessor, real, file)
      end

      def direct(file, method)
        return unless @source.find_line(file, /^\s*def #{Regexp.escape(method)}\b/)

        [Target.new(@source, file, method, nil)]
      end

      def included(side, method)
        return unless side == :retrieval

        @source.lines(FILES[side]).filter_map { |row| row[/include Retrieval::(\w+)/, 1] }.filter_map { |name| direct("#{GRAPH}/retrieval/#{Plastic.snake(name)}.rb", method) }.first
      end

      def writers_of(text, file)
        text.scan(/@writers\.(\w+)(?:\.(\w+))?/).filter_map { |writer, call| class_target("@writers.#{writer}", call, file) }.flatten
      end

      def accessed(text) = @accessors.calls(text).filter_map { |klass, method| built_target(klass, method) }

      def built(text) = text.scan(BUILT).reject { |klass, method| !method && @accessors.class?(klass) }.filter_map { |klass, method| built_target(klass, method) }

      def built_target(klass, method)
        file = constant_file(klass) or return
        Target.new(@source, file, method, klass)
      end

      def hopped(found, hop)
        built = found.filter_map { |target| (klass = target.text[CONSTANT, 1]) && built_target(klass, hop) }
        built.empty? ? found : built
      end

      def class_target(accessor, real, file)
        segment = accessor.delete('":@').split(".").last
        klass = class_name(segment, accessor.include?("@writers") ? WRITERS : file) or return
        found = constant_file(klass) or return
        [Target.new(@source, found, [real, segment].compact.first, klass)]
      end

      def class_name(segment, file)
        pattern = /def #{segment}\b.*#{CONSTANT}|built\(:#{segment}\)\s*\{.*#{CONSTANT}/
        @source.lines(file).grep(pattern).first&.then { |text| text[CONSTANT, 1] }
      end
    end
  end
end
