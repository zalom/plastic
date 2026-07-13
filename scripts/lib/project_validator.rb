# encoding: UTF-8
# frozen_string_literal: true

require "yaml"

# ProjectValidator - the single source of truth for "is a project spawn
# complete?" (intent 190).
#
# A project can be registered in projects.yml, have a store, and still be
# missing the pieces a real project needs: project.yml, a root AGENTS.md.
# The intent-26 spawn shipped exactly that shape and was caught only by a
# much later, pull-only plastic-doctor sweep. This module lets
# plastic-project-creating verify a spawn BEFORE announcing it as done,
# mirroring how scripts/new-intent already runs IntentValidator before
# announcing a new intent (validate-intent).
#
# Pure and dependency-injected: validate accepts an injectable plastic_home,
# uses no eval, performs no file writes, no global-constant injection.
# scripts/doctor.rb's check_project_store already covers 4 of these 6
# invariants (project_dir_exists, project_store_dir, project_index,
# project_yml_exists) plus cross_references, advisorially and pull-only;
# doctor adopting this module is a named follow-up, not part of this intent
# (D8). Invariant 4 (project-root AGENTS.md) has no existing check anywhere.
module ProjectValidator
  module_function

  def validate(slug, plastic_home: File.join(Dir.home, ".plastic"))
    missing = []
    errors = []

    entry = registration_for(slug, plastic_home)
    unless entry
      missing << "projects.yml registration"
      errors << "project '#{slug}' is not registered in projects.yml with a 'path' key"
      return { ok: false, missing: missing, errors: errors }
    end

    project_path = entry["path"].to_s

    # Invariant 2: registered project directory exists on disk.
    unless File.directory?(project_path)
      missing << "project directory"
      errors << "registered project directory does not exist: #{project_path}"
    end

    project_dir = File.join(plastic_home, "projects", slug)

    # Invariant 3: project.yml exists AND parses as YAML.
    project_yml_path = File.join(project_dir, "project.yml")
    if File.exist?(project_yml_path)
      parsed = begin
        YAML.safe_load(File.read(project_yml_path))
      rescue StandardError
        nil
      end
      unless parsed.is_a?(Hash)
        missing << "project.yml (valid YAML)"
        errors << "project.yml exists at #{project_yml_path} but does not parse as YAML"
      end
    else
      missing << "project.yml"
      errors << "project.yml missing at #{project_yml_path}"
    end

    # Invariant 4: project-root AGENTS.md (the registered path, NOT
    # ~/.plastic/projects/{slug}/). This is the intent-26 spawn's gap,
    # uncaught by doctor.rb today.
    agents_md_path = File.join(project_path, "AGENTS.md")
    unless File.exist?(agents_md_path)
      missing << "AGENTS.md (project root)"
      errors << "AGENTS.md missing at project root: #{agents_md_path}"
    end

    # Invariant 5: store/ exists.
    store_dir = File.join(project_dir, "store")
    unless File.directory?(store_dir)
      missing << "store/"
      errors << "store directory missing: #{store_dir}"
    end

    # Invariant 6: INDEX.md exists.
    index_md_path = File.join(project_dir, "INDEX.md")
    unless File.exist?(index_md_path)
      missing << "INDEX.md"
      errors << "INDEX.md missing: #{index_md_path}"
    end

    { ok: missing.empty?, missing: missing, errors: errors }
  end

  # Invariant 1: registered in projects.yml with a 'path'. Returns the
  # project's entry Hash, or nil when unregistered or the entry has no path.
  def registration_for(slug, plastic_home)
    projects = load_projects(plastic_home)
    entry = projects[slug]
    entry.is_a?(Hash) && entry["path"] ? entry : nil
  end

  # Parse projects.yml -> the `projects` Hash, or {} on any error/absence.
  # Mirrors StoreProvisioning.load_projects.
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
end
