# frozen_string_literal: true

module CommandReference
  # The tools a command reading needs, built once.
  Kit = Data.define(:source, :root, :table, :schema, :scan, :endings, :prints)

  # A command's class name from the table, loaded on demand.
  CommandName = Data.define(:full) do
    def klass
      return Object.const_get(full) if full.start_with?("Fixtures::")

      require "plastic/#{directory}/#{Plastic.snake(full.split("::").last)}"
      Plastic.const_get(full)
    end

    def directory = full.start_with?("Hooks::") ? "hooks" : "commands"
  end

  # Reads one command from the kernel into a Page.
  class CommandReading
    KINDS = [[Plastic::Routine, :routine], [Plastic::Hook, :hook]].freeze

    def self.of(kit, value)
      table = kit.table
      return new(kit, value, CommandName.new(table.fetch(value).first).klass) if value.is_a?(String)

      new(kit, table.find { |_words, (name, _summary)| value.name.end_with?(name) }.first, value)
    end

    def initialize(kit, words, klass)
      @kit = kit
      @words = words
      @klass = klass
    end

    def page
      reach = Reach.new(kind:, files: end_files, flows:, own_call:)
      Page.new(**identity, kind: reach.kind, own_call: reach.own_call, flows: reach.flows, edges:, touches: touches(reach), endings: @kit.endings.call(reach))
    end

    private

    def identity
      { words: @words, klass: @klass, file:, line:, summary: @kit.table.dig(@words, 1), comment: @kit.source.class_comment(@klass),
        usage: @klass.usage_line(@words), arguments: @klass.arguments, options: @klass.options, entry: chain&.entry }
    end

    def file = @kit.source.relative(Object.const_source_location(@klass.name).first)

    def line = Object.const_source_location(@klass.name).last

    def kind = KINDS.find { |type, _| @klass <= type }&.last || :command

    def routine? = @klass <= Plastic::Routine

    def hook? = @klass <= Plastic::Hook

    def chain = (@klass.chain if routine?)

    def flows = Array(chain&.then { |found| FlowReader.new(@kit.source, found).all })

    def edges
      Array(chain&.edges).group_by { |edge| [edge.from, edge.to] }.reject { |(_from, to), _| to == :noop }
        .map { |(from, to), group| Edge.new(from, to, group.map(&:on)) }
    end

    def touches(reach)
      found = @kit.scan.call(reach.scanned_files)
      Touches.new(entries: found.entries, components: found.components, files: @kit.prints.files(@klass.prints), schema: @kit.schema, declared: { read: @klass.reads, write: @klass.writes })
    end

    def end_files
      home = file
      [home, own_call&.file, *(HookFiles.new(@kit, home).call if hook?)].compact.uniq
    end

    def own_call = OwnCallReading.new(@kit.source, @klass).call
  end
end
