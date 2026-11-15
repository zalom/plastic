# frozen_string_literal: true

require "find"

# The files of a checkout, read from the disk: every file under the root
# except the git folder and each path that a pattern of the root .gitignore names.
module RepositoryFiles
  def self.paths(root)
    patterns = patterns_of(File.join(root, ".gitignore"))
    found = []
    Find.find(root) do |path|
      relative = path.delete_prefix("#{root}/")
      next if path == root
      next Find.prune if relative == ".git" || ignored?(relative, patterns)

      found << relative if File.file?(path)
    end
    found.sort
  end

  def self.patterns_of(file)
    return [] unless File.file?(file)

    File.readlines(file, chomp: true).map(&:strip).reject { |line| line.empty? || line.start_with?("#") }
  end

  def self.ignored?(relative, patterns) = patterns.any? { |pattern| matches?(relative, pattern.delete_suffix("/").delete_prefix("/"), pattern.include?("/")) }

  def self.matches?(relative, pattern, anchored)
    return File.fnmatch?(pattern, relative, File::FNM_PATHNAME | File::FNM_DOTMATCH) if anchored

    File.fnmatch?(pattern, File.basename(relative), File::FNM_DOTMATCH)
  end
  private_class_method :patterns_of, :ignored?, :matches?
end
