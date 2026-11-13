# frozen_string_literal: true

module Plastic
  module Graph
    module Knowledge
      # The fields of the front matter at the top of an intent file.
      class FrontMatter
        BLOCK = /\A---\n(.*?)\n---/m
        FIELD = /^(\w+):[ \t]*"?([^"\n]*?)"?[ \t]*$/

        def self.fields(text) = text[BLOCK, 1].to_s.scan(FIELD).to_h

        def initialize(folder)
          @folder = folder
        end

        def read(dir)
          file = @folder.own_file(dir)
          self.class.fields(@folder.exist?(file) ? @folder.read(file).force_encoding(Encoding::UTF_8) : "")
        end
      end
    end
  end
end
