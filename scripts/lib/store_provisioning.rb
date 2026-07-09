# encoding: UTF-8
# frozen_string_literal: true

require "fileutils"
require "yaml"
require_relative "worktree"

# StoreProvisioning — the single source of truth for creating a registered
# project's intent store (intent 61).
#
# A project can be registered in `projects.yml` yet have no store on disk. This
# module deterministically and idempotently provisions that store at
# `~/.plastic/projects/{slug}/store`: it makes the store directory, then writes,
# only if missing, `.gitkeep`, `INDEX.md` (from templates/index.md), and
# `project.yml` (from templates/project.yml). Re-running never clobbers existing
# files. The logic was migrated here from the orphaned
# `InstallerCore#bootstrap_project_store` so there is one definition that the
# `provision-project-store` CLI, the `plastic-add-project-store` skill, the
# doctor fix hint, and the project skills all consult.
#
# Pure filesystem and dependency-injected: `provision` accepts an injectable
# `plastic_home` and `package_root` (so templates resolve from a known root and
# tests stay hermetic), uses no `eval`, performs no qmd mutation, no `system`
# or `spawn`, no network, and no global-constant injection. An unknown or
# unregistered slug creates nothing and returns an error result.
module StoreProvisioning
  module_function

  # Repo root resolved from this file's location (scripts/lib/), so templates
  # resolve at package_root/templates/...; tests can inject a fake package_root.
  PACKAGE_ROOT = File.expand_path("../..", __dir__)

  # Provision the store for a registered project.
  #
  # Returns a result hash mirroring IntentValidator.validate's hash style:
  #   { ok: true, store_dir: "...", created: [paths written this run] }
  #   { ok: false, error: "..." }                (nothing is created)
  def provision(slug, plastic_home: File.join(Dir.home, ".plastic"),
                package_root: PACKAGE_ROOT)
    unless registered?(slug, plastic_home)
      return {
        ok: false,
        error: "project '#{slug}' is not registered in projects.yml; " \
               "provisioning requires the project to already be registered",
      }
    end

    project_dir = File.join(plastic_home, "projects", slug)
    store_dir = File.join(project_dir, "store")
    FileUtils.mkdir_p(store_dir)

    # Every project store (and the global store) shares ONE git repo rooted at
    # plastic_home (there is no per-project .git), so a single unanchored
    # `.gitignore` entry there covers `plastic.db`/`plastic.db-wal`/
    # `plastic.db-shm` at any depth under it, present store or future one. The
    # DB itself is never created here: SQLite creates the file lazily on first
    # `Plastic::DB.connect` (D3), and this call must never force that early.
    Worktree.ensure_gitignored(plastic_home, "plastic.db*")

    created = []
    created << write_if_missing(File.join(store_dir, ".gitkeep"), "")

    index_template = File.join(package_root, "templates", "index.md")
    if File.exist?(index_template)
      created << write_if_missing(File.join(project_dir, "INDEX.md"),
                                  File.read(index_template))
    end

    project_template = File.join(package_root, "templates", "project.yml")
    if File.exist?(project_template)
      created << write_if_missing(File.join(project_dir, "project.yml"),
                                  File.read(project_template))
    end

    { ok: true, store_dir: store_dir, created: created.compact }
  end

  # True iff `slug` is a key under the `projects` mapping in projects.yml.
  # Reads with a rescue-to-safe-default reader so a malformed file never raises.
  def registered?(slug, plastic_home)
    projects = load_projects(plastic_home)
    projects.is_a?(Hash) && projects.key?(slug)
  end

  # Parse projects.yml -> the `projects` Hash, or {} on any error/absence.
  # Mirrors QmdSync#load_projects (scripts/lib/qmd_sync.rb).
  def load_projects(plastic_home)
    path = File.join(plastic_home, "projects.yml")
    return {} unless File.exist?(path)

    data = begin
      YAML.safe_load(File.read(path)) || {}
    rescue StandardError
      {}
    end
    projects = data.is_a?(Hash) ? data["projects"] : nil
    projects.is_a?(Hash) ? projects : {}
  end

  # Write `content` to `path` only when `path` does not exist. Returns the path
  # when a file was written, or nil when the file already existed (so callers
  # can build a `created` list). Copied from InstallerCore#write_if_missing.
  def write_if_missing(path, content)
    return nil if File.exist?(path)

    File.write(path, content)
    path
  end
end
