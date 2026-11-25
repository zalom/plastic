# frozen_string_literal: true

module CommandReference
  # The files a hook loads next to its own file with require_relative.
  class HookFiles
    def initialize(kit, home)
      @kit = kit
      @home = home
    end

    def call
      names = @kit.source.lines(@home).filter_map { |text| text[/require_relative "(\w+)"/, 1] }
      names.map { |name| File.join(File.dirname(@home), "#{name}.rb") }.select { |path| File.file?(File.join(@kit.root, path)) }
    end
  end
end
