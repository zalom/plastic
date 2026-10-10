# frozen_string_literal: true

module CommandReference
  # Builds a Page for each command of the command table.
  class Model
    attr_reader :source, :schema

    def initialize(root, table: Plastic::CLI::TABLE)
      @root = root
      @table = table
      @source = Source.new(root)
      @schema = Schema.new(root)
      @scan = Touches::Scan.new(@source, Touches::Facade.new(@source, root), @schema)
      @endings = Endings.new(@source)
      @prints = Prints.new(@source)
    end

    def page(words_or_class)
      words, klass = identify(words_or_class)
      file, line = Object.const_source_location(klass.name)
      chain = klass.chain if klass.respond_to?(:chain)
      flows = chain ? chain.keys.map { |key| FlowReader.new(@source, chain).call(key) } : []
      build(words:, klass:, file: @source.relative(file), line:, chain:, flows:)
    end

    private

    def identify(value)
      return [value, command_class(value)] if value.is_a?(String)

      [@table.find { |_words, (name, _summary)| value.name.end_with?(name) }.first, value]
    end

    def command_class(words)
      name = @table.fetch(words).first
      return Object.const_get(name) if name.start_with?("Fixtures::")

      directory = name.start_with?("Hooks::") ? "hooks" : "commands"
      require "plastic/#{directory}/#{Plastic.snake(name.split("::").last)}"
      Plastic.const_get(name)
    end

    def kind(klass)
      return :routine if klass <= Plastic::Routine

      (klass <= Plastic::Hook) ? :hook : :command
    end

    def build(words:, klass:, file:, line:, chain:, flows:)
      own = own_call(klass)
      Page.new(words:, klass:, kind: kind(klass), file:, line:, summary: @table.dig(words, 1), comment: @source.class_comment(klass),
        usage: klass.usage_line(words), arguments: klass.arguments, options: klass.options, own_call: own, entry: chain&.entry,
        flows:, edges: edges(chain), touches: touches(klass, file, flows, own),
        endings: @endings.call(kind(klass), end_files(klass, file, own), flows, own))
    end

    def touches(klass, file, flows, own)
      files = [*end_files(klass, file, own), *flows.flat_map { |flow| flow.rows.filter_map(&:file) + [flow.file] }].uniq
      found = @scan.call(files)
      Touches.new(entries: found.entries, components: found.components, files: @prints.files(klass.prints), schema: @schema)
    end

    def end_files(klass, file, own) = [file, own&.file, *hook_files(klass, file)].compact.uniq

    def hook_files(klass, file)
      return [] unless klass <= Plastic::Hook

      @source.lines(file).filter_map { |text| text[/require_relative "(\w+)"/, 1] }
        .map { |name| File.join(File.dirname(file), "#{name}.rb") }.select { |path| File.file?(File.join(@root, path)) }
    end

    def own_call(klass)
      method = klass.instance_method((klass <= Plastic::Hook) ? :respond : :call)
      return if [Plastic::Routine, Plastic::CLI::Command, Plastic::Hook].include?(method.owner)

      file, line = method.source_location
      file = @source.relative(file)
      OwnCall.new(file, line, @source.method_lines(file, line))
    end

    def edges(chain)
      return [] unless chain

      chain.edges.reject { |edge| edge.to == :noop }.group_by { |edge| [edge.from, edge.to] }
        .map { |(from, to), group| Edge.new(from, to, group.map(&:on)) }
    end
  end
end
