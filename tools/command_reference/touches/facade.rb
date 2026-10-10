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
      CONSTANT = /([A-Z]\w*(?:::[A-Z]\w*)*)\.new/
      BUILT = /#{CONSTANT}(?:\([^)]*\))?(?:\.(\w+[?!]?))?/
      ACCESSOR = /^\s*def (\w+)\s*=.*?#{CONSTANT}|built\(:(\w+)\)\s*\{.*?#{CONSTANT}/

      def initialize(source, root)
        @source = source
        @root = root
        @delegations = {}
      end

      def targets(side, method, hop = nil)
        file = FILES.fetch(side)
        found = delegated(file, method) || direct(file, method) || included(side, method) || []
        hop ? hopped(found, hop) : found
      end

      def follow(target)
        text = target.text
        [*writers_of(text, target.file), *(accessors(text) unless target.component), *built(text)]
      end

      def constant_file(klass)
        tail = klass.split("::").last(2).map { |part| Plastic.snake(part) }.join("/")
        Dir.glob("#{@root}/#{GRAPH}/**/#{tail}.rb").map { |path| @source.relative(path) }.min
      end

      private

      def delegated(file, method)
        accessor, real = delegations(file)[method]
        accessor && class_target(accessor, real, file)
      end

      def direct(file, method)
        return unless @source.find_line(file, /^\s*def #{Regexp.escape(method)}\b/)

        [Target.new(@source, file, method, nil)]
      end

      def included(side, method)
        return unless side == :retrieval

        modules(FILES[side]).filter_map { |file| direct(file, method) }.first
      end

      def modules(file)
        @source.lines(file).filter_map { |row| row[/include Retrieval::(\w+)/, 1] }.map { |name| "#{GRAPH}/retrieval/#{Plastic.snake(name)}.rb" }
      end

      def writers_of(text, file)
        text.scan(/@writers\.(\w+)(?:\.(\w+))?/).filter_map { |writer, call| class_target("@writers.#{writer}", call, file) }.flatten
      end

      def accessors(text)
        accessor_table.flat_map do |name, klass|
          text.scan(/(?<![\w.@:])(?<!def )#{Regexp.escape(name)}(?![\w:?!(])(?:\.(\w+[?!]?))?/).flatten.uniq.filter_map { |method| built_target(klass, method) }
        end
      end

      def accessor_table
        @accessor_table ||= FILES.values.flat_map { |file| @source.lines(file).filter_map { |row| accessor_of(row) } }.to_h
      end

      def accessor_of(row)
        found = row.match(ACCESSOR) or return
        [found[1] || found[3], found[2] || found[4]]
      end

      def built(text) = text.scan(BUILT).reject { |klass, method| method.nil? && accessor_table.value?(klass) }.filter_map { |klass, method| built_target(klass, method) }

      def built_target(klass, method)
        file = constant_file(klass) or return
        Target.new(@source, file, method, klass)
      end

      def hopped(found, hop)
        built = found.flat_map { |target| helper(target, hop) }
        built.empty? ? found : built
      end

      def helper(target, hop)
        klass = target.text[CONSTANT, 1] or return []
        file = constant_file(klass) or return []
        [Target.new(@source, file, hop, klass)]
      end

      def delegations(file) = (@delegations[file] ||= Delegations.new(@source, file).table)

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
