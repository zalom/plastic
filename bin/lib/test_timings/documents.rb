# frozen_string_literal: true

require "json"

module TestTimings
  # Books a finished Minitest result to the file it ran from, or, when its
  # class is one a Varar document generated, to that document. Every class a
  # Varar document generates is defined inside the varar-minitest gem's own
  # file, so a result's method source location always points there and
  # never at the document; the document list, read from varar.config.json,
  # is what tells the two apart.
  class Documents
    CONFIG_FILE = "varar.config.json"

    def initialize(root: File.expand_path("../../..", __dir__))
      @root = root
    end

    def book(result)
      klass = result.klass
      class_names.fetch(klass) { file_of(klass, result.name) }
    end

    private

    def class_names
      @class_names ||= documents.to_h { |path| [varar_class_name(path), path] }
    end

    def documents
      config_path = File.join(@root, CONFIG_FILE)
      return [] unless File.exist?(config_path)

      included_globs(config_path).flat_map { |glob| Dir.glob(File.join(@root, glob)) }
        .map { |full| full.delete_prefix("#{@root}/") }.sort
    end

    def included_globs(config_path)
      Array(JSON.parse(File.read(config_path)).dig("docs", "include"))
    end

    def varar_class_name(path)
      require "varar/minitest"
      "Var_#{Varar::Minitest.identifier(path)}"
    end

    def file_of(klass, name)
      Object.const_get(klass).instance_method(name).source_location.first.delete_prefix("#{@root}/")
    end
  end
end
