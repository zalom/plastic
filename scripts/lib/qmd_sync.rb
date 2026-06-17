# encoding: UTF-8
# frozen_string_literal: true

require "yaml"

# QmdSync — the single place Plastic talks to QMD (intent 45a).
#
# Plastic computes only the Plastic-specific inputs (which store directory maps to
# which `plastic-`prefixed collection, derived from projects.yml, plus a short
# context description). The actual indexing is delegated to the `qmd` CLI; this
# module never reimplements QMD's logic. QMD is optional: every public entry
# no-ops cleanly when `qmd` is not on PATH.
#
# Pure and dependency-injected: all shelling-out goes through an injected
# `runner` callable, so the whole module is unit-testable with no real binary,
# no network, and no model downloads. The default runner shells out to `qmd`.
module QmdSync
  module_function

  CONTEXT_DESCRIPTION =
    "Plastic intent store: intents, specs, plans, checklists, outcomes, and insights " \
    "for the What/Why/How/Exec lifecycle. Search here for past decisions and work."

  # A runner is `->(args_array) { [stdout_string, success_boolean] }`.
  # The default invokes the real `qmd` binary.
  def default_runner
    lambda do |args|
      require "open3"
      out, _err, status = Open3.capture3("qmd", *args)
      [out, status.success?]
    end
  end

  # True when `qmd` is resolvable on PATH. The probe is injectable so tests do
  # not depend on the host having qmd installed.
  def detect(path_probe: method(:which_qmd))
    !!path_probe.call
  end

  def which_qmd
    ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |dir|
      candidate = File.join(dir, "qmd")
      File.file?(candidate) && File.executable?(candidate)
    end
  end

  # Collection name for a store directory.
  #   global store (<plastic_home>/store)        -> "plastic-global"
  #   project store (<.../projects/<slug>/store) -> "plastic-<slug>"
  # Slug is resolved from projects.yml by matching the project path; falls back
  # to the directory's parent name when no registry match exists.
  def collection_name(store_dir, plastic_home:)
    store_dir = File.expand_path(store_dir)
    global_store = File.expand_path(File.join(plastic_home, "store"))
    return "plastic-global" if store_dir == global_store

    slug = slug_for_store(store_dir, plastic_home: plastic_home)
    "plastic-#{slug}"
  end

  # Every store Plastic knows about: the global store plus each registered
  # project store. Returns [{collection:, dir:}, ...].
  def enumerate_stores(plastic_home:)
    stores = [{
      collection: "plastic-global",
      dir: File.expand_path(File.join(plastic_home, "store")),
    }]

    projects = load_projects(plastic_home)
    projects.each do |slug, info|
      path = info.is_a?(Hash) ? info["path"] : nil
      next unless path
      project_store = File.join(File.expand_path(path), "store")
      # Project stores live under ~/.plastic/projects/<slug>/store as the mirror;
      # registry `path` is the project code dir, so the tactical store is the
      # plastic_home projects mirror.
      mirror_store = File.expand_path(File.join(plastic_home, "projects", slug.to_s, "store"))
      dir = Dir.exist?(mirror_store) ? mirror_store : project_store
      stores << { collection: "plastic-#{slug}", dir: dir }
    end
    stores
  end

  # Register a store directory as a collection and attach the Plastic context
  # description. Idempotent: re-running is safe. No-op when qmd is absent.
  def register(collection:, dir:, runner: default_runner, context: CONTEXT_DESCRIPTION, detector: method(:detect))
    return skip_result unless detector.call
    out1, ok1 = runner.call(["collection", "add", dir, "--name", collection])
    _out2, ok2 = runner.call(["context", "add", collection, context])
    { ran: true, ok: (ok1 && ok2), output: out1.to_s.strip }
  end

  # Re-index a single collection: refresh the corpus then its embeddings.
  # Scoped embed (-c) keeps delivery-time reindex fast. No-op when qmd absent.
  def reindex(collection:, runner: default_runner, detector: method(:detect))
    return skip_result unless detector.call
    _o1, ok1 = runner.call(["update"])
    _o2, ok2 = runner.call(["embed", "-c", collection])
    { ran: true, ok: (ok1 && ok2) }
  end

  # Read-only status used by doctor and the session-start report line.
  # Returns a structured hash; never mutates the index.
  def status(plastic_home:, runner: default_runner, detector: method(:detect))
    return { present: false } unless detector.call

    expected = enumerate_stores(plastic_home: plastic_home).map { |s| s[:collection] }
    listed = list_collections(runner)
    missing = expected - listed

    { present: true, expected: expected, registered: listed,
      missing: missing, all_registered: missing.empty? }
  end

  # --- internals ---

  def skip_result
    { ran: false, ok: true, skipped: true }
  end

  def list_collections(runner)
    out, ok = runner.call(["collection", "list"])
    return [] unless ok && out
    # qmd prints lines like "plastic-global (qmd://plastic-global/)"; pull the
    # leading collection token off each non-indented line.
    out.lines.filter_map do |line|
      next if line.start_with?(" ", "\t")
      m = line.strip.match(/\A([A-Za-z0-9][\w.-]*)\b/)
      m && m[1]
    end.reject { |t| %w[Collections No].include?(t) }
  end

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

  def slug_for_store(store_dir, plastic_home:)
    projects = load_projects(plastic_home)
    projects.each do |slug, info|
      path = info.is_a?(Hash) ? info["path"] : nil
      next unless path
      project_root = File.expand_path(path)
      mirror = File.expand_path(File.join(plastic_home, "projects", slug.to_s, "store"))
      return slug.to_s if store_dir == File.join(project_root, "store") || store_dir == mirror
    end
    # Fallback: <...>/projects/<slug>/store -> slug, else parent dir name.
    parts = store_dir.split(File::SEPARATOR)
    idx = parts.rindex("projects")
    return parts[idx + 1] if idx && parts[idx + 1] && parts[idx + 2] == "store"
    File.basename(File.dirname(store_dir))
  end
end
