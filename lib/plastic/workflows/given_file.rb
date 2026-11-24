# frozen_string_literal: true

module Plastic
  module Workflows
    # Reads the file a command's --from names as UTF-8 text.
    module GivenFile
      # The text of the file and nil, or nil and why it cannot be read; `name` says what the file holds.
      def self.text(path, name)
        text = File.binread(path).force_encoding(Encoding::UTF_8)
        text.valid_encoding? ? [text, nil] : [nil, "the #{name} file #{path} is not UTF-8 text"]
      rescue SystemCallError => error
        [nil, "the #{name} file cannot be read: #{error.message}"]
      end
    end
  end
end
