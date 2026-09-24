# encoding: UTF-8
# frozen_string_literal: true

require "shellwords"

# CodexAdapter (intent 340b, G7c, n6): the `codex exec` argv one node's kind
# needs. Intent 391: Plastic prints this command beside the dispatch line
# and never runs it; the Codex session that reads the plan runs it.
#
# Pure: sandbox_mode, git_dir_for_worktree, add_dir_args, build_argv and
# command_line touch nothing but the filesystem read they are explicitly
# given (the worktree's own `.git` file), never a git call and never a
# guess at a repository root.
module CodexAdapter
  module_function

  # Verify and research get NO write access at all (spec D9): read-only, no
  # `--add-dir`. Everything else - work, and any kind this table has never
  # heard of - gets the widest treatment, matching RunnerPolicy's own
  # unknown-kind-falls-back-to-work rule (matrix row 6.10).
  READ_ONLY_KINDS = %w[verify research].freeze

  def sandbox_mode(kind)
    READ_ONLY_KINDS.include?(kind.to_s) ? "read-only" : "workspace-write"
  end

  # The repository's OWN `.git` directory, derived from `worktree`'s `.git`
  # FILE (a git worktree never carries a real `.git` directory of its own -
  # spec) rather than any guess at how many path segments separate a
  # worktree from its repo (matrix row 6.6). `.git` reads
  # `gitdir: <repo>/.git/worktrees/<name>`; two directories up from that
  # target is the repository's real `.git`. Returns nil when `worktree` is
  # not a git worktree at all (no `.git` file, or `.git` is a directory,
  # meaning `worktree` is a repository's own primary checkout) - callers
  # treat that as "no `--add-dir` to add", never as a reason to guess.
  def git_dir_for_worktree(worktree)
    gitfile = File.join(worktree.to_s, ".git")
    return nil unless File.file?(gitfile)

    content = File.read(gitfile)
    m = content.match(/\Agitdir:\s*(.+?)\s*\z/m)
    return nil unless m

    worktrees_entry = File.expand_path(m[1], worktree.to_s)
    File.dirname(File.dirname(worktrees_entry))
  end

  # [] for a read-only kind (matrix row 6.4): `-C` already makes the
  # worktree writable, and `--add-dir` on top of `--sandbox read-only` would
  # contradict the sandbox mode itself. Exactly one `--add-dir`, the
  # repository's own `.git`, for every other kind (matrix row 6.5) - nil
  # when the worktree's own gitdir pointer cannot be resolved, so a caller
  # handed a plain (non-worktree) directory never gets a bogus argument.
  def add_dir_args(kind:, worktree:)
    return [] if READ_ONLY_KINDS.include?(kind.to_s)

    git_dir = git_dir_for_worktree(worktree)
    git_dir ? ["--add-dir", git_dir] : []
  end

  # The whole `codex exec` argv for one node (matrix rows 6.1-6.9): `-C` at
  # the worktree given (row 6.8), the sandbox mode and `--add-dir` this
  # kind's row calls for and nothing else (row 6.7 - never the intent
  # worktree, never `~/.plastic`), and a bare `-` so the prompt is read from
  # stdin (row 6.9) - the node input itself never rides in this array.
  def build_argv(kind:, worktree:, model: nil, effort: nil)
    argv = [
      "codex", "exec",
      *(worktree.to_s.empty? ? [] : ["-C", worktree.to_s]),
      "--sandbox", sandbox_mode(kind),
      *add_dir_args(kind: kind, worktree: worktree),
    ]
    argv += ["--model", model.to_s] unless model.to_s.strip.empty?
    argv += ["--config", %(model_reasoning_effort="#{effort}")] unless effort.to_s.strip.empty?
    argv + ["-"]
  end

  def command_line(kind:, worktree:, input:, model: nil, effort: nil)
    "#{Shellwords.join(build_argv(kind: kind, worktree: worktree, model: model, effort: effort))} < #{Shellwords.escape(input.to_s)}"
  end
end
