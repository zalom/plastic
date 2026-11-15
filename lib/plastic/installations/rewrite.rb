# frozen_string_literal: true

require "fileutils"
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

      # The file a link points to, so a write keeps the link; any other path stays.
      def self.target(path)
        File.symlink?(path) ? File.realpath(path) : path
      rescue Errno::ENOENT
        path
      end

      def self.replace(path, text)
        final = target(path)
        temporary = "#{final}.plastic-tmp.#{Process.pid}"
        File.write(temporary, text)
        File.rename(temporary, final)
      rescue
        FileUtils.rm_f(temporary)
        raise
      end
    end
  end
end
