# frozen_string_literal: true

require "fileutils"

module CommandReference
  # The reference files as they sit in the repository.
  class Disk
    FOLDERS = %w[docs/reference/commands docs/reference/dsl].freeze

    def initialize(root)
      @root = root
    end

    def files = paths.to_h { |path| [path, File.read(absolute(path))] }

    def write(files)
      (paths - files.keys).each { |path| FileUtils.rm_f(absolute(path)) }
      files.each { |path, text| put(path, text) }
      prune
    end

    private

    def absolute(*parts) = File.join(@root, *parts)

    def paths = FOLDERS.flat_map { |folder| listed(folder) }.select { |path| File.file?(absolute(path)) }

    def listed(folder) = Dir.glob("**/*", base: absolute(folder)).sort.map { |path| File.join(folder, path) }

    def put(path, text)
      target = absolute(path)
      FileUtils.mkdir_p(File.dirname(target))
      File.write(target, text) unless File.exist?(target) && File.read(target) == text
    end

    def prune = FOLDERS.flat_map { |folder| nested(folder) }.each { |dir| Dir.rmdir(dir) if Dir.empty?(dir) }

    def nested(folder) = Dir.glob("**/*/", base: absolute(folder)).sort.reverse.map { |dir| absolute(folder, dir) }
  end
end
