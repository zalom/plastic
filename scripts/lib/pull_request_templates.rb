# encoding: UTF-8
# frozen_string_literal: true

# PullRequestTemplates (intent 390) - read-only detection of a repository's
# own pull request or merge request template files, so the commit
# instruction `plastic session commit` prints can name the exact command
# that honors one. File checks only: no git, gh, or glab call, and no
# preference for one hosting service over another (both GitHub and GitLab
# paths are read).
module PullRequestTemplates
  module_function

  GITHUB_GLOBS = [
    ".github/pull_request_template.md",
    ".github/PULL_REQUEST_TEMPLATE.md",
    ".github/PULL_REQUEST_TEMPLATE/*.md",
    "docs/pull_request_template.md",
  ].freeze

  GITLAB_GLOBS = [
    ".gitlab/merge_request_templates/*.md",
  ].freeze

  GLOBS = (GITHUB_GLOBS + GITLAB_GLOBS).freeze

  # Existing template files under `repo`, one path per match, sorted for a
  # deterministic instruction order. Nothing is read but the file list.
  def detect(repo)
    return [] if repo.to_s.strip.empty?

    GLOBS.flat_map { |pattern| Dir.glob(File.join(repo, pattern)) }.uniq.sort
  end

  # One instruction line per detected template: `gh pr create --template
  # NAME.md` for a GitHub path, `glab mr create --template NAME` (no
  # extension) for a GitLab path.
  def instructions(repo)
    detect(repo).map { |path| instruction_for(path) }
  end

  def instruction_for(path)
    name = File.basename(path)
    if path.include?("#{File::SEPARATOR}.gitlab#{File::SEPARATOR}")
      "glab mr create --template #{name.sub(/\.md\z/, "")}"
    else
      "gh pr create --template #{name}"
    end
  end
end
