# frozen_string_literal: true

require "digest"
require "json"

module Plastic
  module Graph
    module Prints
      # One file and how to make it. `source` gives the bytes only when the
      # file must be written, so a kept file is compared by its hash alone.
      Print = Data.define(:path, :database, :sha256, :source)

      # How a print compares with its file and its record.
      class Print
        def self.text(path, database, text) = new(path, database, Digest::SHA256.hexdigest(text), -> { text })

        def text = source.call

        # The file holds these bytes already.
        def level?(folder) = folder.digest(path) == sha256

        # The file holds the JSON of this print in other bytes: a formatter's bytes, not a person's edit.
        def same_json?(folder)
          sha256 && JSON.parse(folder.read(path).force_encoding(Encoding::UTF_8)) == JSON.parse(text)
        rescue JSON::ParserError
          false
        end

        def write_to(folder) = folder.write(path, text)

        # The last print recorded these bytes.
        def recorded?(recorded) = recorded[path] == sha256

        def printed_row = { path:, sha256:, at: Plastic.now }
      end
    end
  end
end
