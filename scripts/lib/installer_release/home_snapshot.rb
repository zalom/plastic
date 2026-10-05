# frozen_string_literal: true

require "fileutils"

module InstallerRelease
  # A copy of the managed home paths taken before an activation. Putting it
  # back removes every managed path the activation left, including new ones,
  # and copies the saved paths back without following links.
  class HomeSnapshot
    PRESENT = ->(path) { File.exist?(path) || File.symlink?(path) }

    def initialize(directory, paths)
      @directory = directory
      @paths = paths
    end

    def take
      FileUtils.mkdir_p(directory)
      paths.call.select(&PRESENT).each_with_index.map do |path, index|
        name = index.to_s
        FileUtils.copy_entry(path, File.join(directory, name))
        [path, name]
      end
    end

    def put_back(saved)
      (paths.call | saved.map(&:first)).each { |path| FileUtils.rm_rf(path) }
      saved.each do |path, name|
        FileUtils.mkdir_p(File.dirname(path))
        FileUtils.copy_entry(File.join(directory, name), path)
      end
    end

    private

    attr_reader :directory, :paths
  end
end
