# frozen_string_literal: true

require "json"

module Plastic
  module Installations
    # Writes a changed settings or instruction file in one rename, or deletes
    # it when nothing is left in it. Each writer returns the path.
    module Rewrite
      def self.json(path, data)
        data.empty? ? File.delete(path) : replace(path, "#{JSON.pretty_generate(data)}\n")
        path
      end

      def self.text(path, text)
        text.strip.empty? ? File.delete(path) : replace(path, "#{text.rstrip}\n")
        path
      end

      def self.replace(path, text)
        temporary = "#{path}.plastic-tmp.#{Process.pid}"
        File.write(temporary, text)
        File.rename(temporary, path)
      end
    end
  end
end
