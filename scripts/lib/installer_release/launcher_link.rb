# frozen_string_literal: true

module InstallerRelease
  # The launcher in the bin directory. Plastic owns it while it is missing
  # or a link into the share; a launcher the user wrote, or a link to another
  # program, is not Plastic's and stays as it is.
  class LauncherLink
    attr_reader :path

    def initialize(path, share)
      @path = path
      @share = share
    end

    def ours?
      return !File.exist?(path) unless File.symlink?(path)

      File.expand_path(File.readlink(path), File.dirname(path)).start_with?("#{share}/")
    end

    def linked? = File.symlink?(path) && ours?

    private

    attr_reader :share
  end
end
