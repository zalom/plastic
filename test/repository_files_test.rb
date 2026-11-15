# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/repository_files"

class RepositoryFilesTest < Minitest::Test
  IGNORED = <<~PATTERNS
    # a comment

    *.log
    .claude/worktrees/
    coverage/
    .DS_Store
    runtime/bundle/
  PATTERNS

  def tree(files)
    Dir.mktmpdir("repository-files") do |root|
      files.each do |path|
        FileUtils.mkdir_p(File.dirname(File.join(root, path)))
        File.write(File.join(root, path), "x")
      end
      File.write(File.join(root, ".gitignore"), IGNORED)
      yield root
    end
  end

  def test_a_file_the_gitignore_names_is_left_out_and_every_other_file_is_listed
    tree(["lib/a.rb", "docs/b.md", "varar/c.md", "run.log", "lib/deep/run.log", ".DS_Store", "lib/.DS_Store"]) do |root|
      assert_equal %w[.gitignore docs/b.md lib/a.rb varar/c.md], RepositoryFiles.paths(root)
    end
  end

  def test_a_directory_the_gitignore_names_is_left_out_with_everything_under_it
    tree(["a.rb", ".claude/worktrees/x/y.rb", ".claude/settings.json", "coverage/index.html", "runtime/bundle/gem.rb", "runtime/keep.rb"]) do |root|
      assert_equal %w[.claude/settings.json .gitignore a.rb runtime/keep.rb], RepositoryFiles.paths(root)
    end
  end

  def test_the_git_folder_is_never_listed
    tree([".git/config", "a.rb"]) do |root|
      assert_equal %w[.gitignore a.rb], RepositoryFiles.paths(root)
    end
  end

  def test_the_list_of_this_checkout_holds_the_docs_and_the_acceptance_documents
    paths = RepositoryFiles.paths(File.expand_path("..", __dir__))

    assert_includes paths, "docs/contributing/ARCHITECTURE.md"
    assert_includes paths, "varar.lock.json"
    refute(paths.any? { |path| path.start_with?(".git/", ".claude/worktrees/") })
  end
end
