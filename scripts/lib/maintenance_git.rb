# encoding: UTF-8
# frozen_string_literal: true

require "open3"

# MaintenanceGit - git isolation for a maintenance action (intent 197, D12/D13): a fresh
# branch off the CURRENT tip of `base`, the caller's block runs, only the paths the block
# ACTUALLY changed are staged (never `git add -A`), committed, and the branch is merged back
# to `base` as part of the SAME closed operation before this method returns. Nothing strands
# on an unmerged branch; nothing outside the block's own change is ever touched.
#
# Requires a CLEAN working tree before starting (see module doc above for why); refuses
# loudly rather than attempt to distinguish pre-existing dirt from the block's own changes.
# On any error inside the block, the working tree is hard-reset and returned to `base` before
# re-raising, which is SAFE only because the precondition already proved nothing else was
# dirty when the branch was created.
module MaintenanceGit
  module_function

  class NotAGitRepo < StandardError; end
  class DirtyWorkingTree < StandardError; end

  def git_toplevel(dir)
    out, _err, status = Open3.capture3("git", "-C", dir, "rev-parse", "--show-toplevel")
    return nil unless status.success?

    top = out.strip
    top.empty? ? nil : top
  end

  # Bare paths (status prefix stripped), relative to `root`. Empty array on a clean tree.
  def porcelain_paths(root)
    out, _err, status = Open3.capture3("git", "-C", root, "status", "--porcelain")
    return [] unless status.success?

    out.lines.map { |l| l[3..].to_s.strip }.reject(&:empty?)
  end

  # Runs `block` inside a fresh branch off `base`'s current tip. Returns
  # { changed: [...], committed: bool, merged: bool, branch: name }.
  def run_scoped(repo_dir:, branch_name:, commit_message:, base: "main")
    root = git_toplevel(repo_dir)
    raise NotAGitRepo, "#{repo_dir} is not inside a git repository" unless root

    dirty = porcelain_paths(root)
    unless dirty.empty?
      raise DirtyWorkingTree,
            "#{root} has #{dirty.size} uncommitted path(s) before maintenance started; " \
            "commit or stash them first (never swept via git add -A): #{dirty.join(", ")}"
    end

    checkout!(root, base)
    run_git!(root, "checkout", "--quiet", "-b", branch_name)

    begin
      yield
    rescue StandardError
      run_git!(root, "reset", "--hard", "--quiet")
      run_git!(root, "clean", "-fd", "--quiet")
      checkout!(root, base)
      delete_branch(root, branch_name)
      raise
    end

    changed = porcelain_paths(root)
    if changed.empty?
      checkout!(root, base)
      delete_branch(root, branch_name)
      return { changed: [], committed: false, merged: false, branch: branch_name }
    end

    run_git!(root, "add", "--", *changed)
    run_git!(root, "-c", "user.name=Plastic", "-c", "user.email=plastic@localhost",
             "commit", "--quiet", "-m", commit_message)
    checkout!(root, base)
    run_git!(root, "-c", "user.name=Plastic", "-c", "user.email=plastic@localhost",
             "merge", "--quiet", "--no-ff", "-m", "Merge #{branch_name} into #{base}", branch_name)
    delete_branch(root, branch_name)

    { changed: changed, committed: true, merged: true, branch: branch_name }
  end

  def checkout!(root, ref)
    run_git!(root, "checkout", "--quiet", ref)
  end

  def delete_branch(root, name)
    Open3.capture3("git", "-C", root, "branch", "--quiet", "-D", name)
  end

  def run_git!(root, *args)
    _out, err, status = Open3.capture3("git", "-C", root, *args)
    raise "git #{args.join(" ")} failed in #{root}: #{err}" unless status.success?
  end
end
