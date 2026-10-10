# frozen_string_literal: true

require "fileutils"

module CommandReference
  # The reference files as they sit in the repository.
  class Disk
    FOLDERS = %w[docs/reference/commands docs/reference/dsl].freeze

    def initialize(root)
      @root = root
    end

    def files = paths.to_h { |path| [path, File.read(File.join(@root, path))] }

    def write(files)
      (paths - files.keys).each { |path| FileUtils.rm_f(File.join(@root, path)) }
      files.each { |path, text| put(path, text) }
      prune
    end

    private

    def paths
      FOLDERS.flat_map { |folder| Dir.glob("**/*", base: File.join(@root, folder)).sort.map { |path| File.join(folder, path) } }.select { |path| File.file?(File.join(@root, path)) }
    end

    def put(path, text)
      target = File.join(@root, path)
      FileUtils.mkdir_p(File.dirname(target))
      File.write(target, text) unless File.exist?(target) && File.read(target) == text
    end

    def prune
      FOLDERS.each do |folder|
        Dir.glob("**/*/", base: File.join(@root, folder)).sort.reverse.each { |dir| Dir.rmdir(File.join(@root, folder, dir)) if Dir.empty?(File.join(@root, folder, dir)) }
      end
    end
  end
end
