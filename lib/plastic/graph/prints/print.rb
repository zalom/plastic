# frozen_string_literal: true

require "digest"

module Plastic
  module Graph
    module Prints
      # One file and how to make it. `source` gives the bytes only when the
      # file must be written, so a kept file is compared by its hash alone.
      Print = Data.define(:path, :sha256, :source)

      # How a print compares with its file and its record.
      class Print
        def self.text(path, text) = new(path, Digest::SHA256.hexdigest(text), -> { text })

        def text = source.call

        # The file holds these bytes already.
        def level?(folder) = folder.digest(path) == sha256

        def write_to(folder) = folder.write(path, text)

        # The last print recorded these bytes.
        def recorded?(recorded) = recorded[path] == sha256

        def printed_row = { path:, sha256:, at: Plastic.now }
      end
    end
  end
end
