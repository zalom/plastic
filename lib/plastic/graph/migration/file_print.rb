# frozen_string_literal: true

require "fileutils"

module Plastic
  module Graph
    # Prints bytes to a path as one step: it writes a temporary file in the same folder, syncs it to the disk and renames
    # it into place, then syncs the folder. A write that fails part way leaves no file behind.
    module FilePrint
      def self.call(path, bytes)
        folder = File.dirname(path)
        FileUtils.mkdir_p(folder)
        temporary = File.join(folder, ".#{File.basename(path)}.#{Process.pid}.print")
        write(temporary, bytes)
        File.rename(temporary, path)
        File.open(folder, &:fsync)
      ensure
        File.delete(temporary) if temporary && File.exist?(temporary)
      end

      def self.write(path, bytes)
        File.open(path, File::WRONLY | File::CREAT | File::EXCL | File::BINARY, 0o644) do |file|
          file.write(bytes)
          file.fsync
        end
      end
    end
  end
end
