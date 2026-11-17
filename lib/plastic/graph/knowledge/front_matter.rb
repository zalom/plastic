# frozen_string_literal: true

require "json"

module Plastic
  module Graph
    module Knowledge
      # The fields of the front matter at the top of an intent file. A value in double quotes is a JSON string,
      # the way the files are written; any other value is its text.
      class FrontMatter
        BLOCK = /\A---\n(.*?)\n---/m
        FIELD = /^(\w+):[ \t]*(?:("(?:[^"\\\n]|\\.)*")|"?([^"\n]*?)"?)[ \t]*$/

        def self.fields(text) = text[BLOCK, 1].to_s.scan(FIELD).to_h { |name, quoted, plain| [name, quoted ? decoded(quoted) : plain] }

        def self.decoded(quoted)
          JSON.parse(quoted)
        rescue JSON::ParserError
          quoted[1..-2]
        end

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
