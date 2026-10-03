# frozen_string_literal: true

require "fileutils"
require "securerandom"

module InstallerRelease
  # A symbolic link that names one release. It is replaced by renaming a new
  # link over it, so a reader sees the old release or the new one, never none.
  class Pointer
    def initialize(path)
      @path = path
    end

    def target = File.symlink?(path) ? File.readlink(path) : nil

    def version
      file = File.join(path, "VERSION")
      File.file?(file) ? File.read(file).strip : nil
    end

    def point_to(target)
      temporary = "#{path}.#{SecureRandom.hex(8)}"
      File.symlink(target, temporary)
      File.rename(temporary, path)
    ensure
      FileUtils.rm_f(temporary)
    end

    def keep
      saved = target
      yield
    rescue
      saved ? point_to(saved) : FileUtils.rm_f(path)
      raise
    end

    private

    attr_reader :path
  end
end
