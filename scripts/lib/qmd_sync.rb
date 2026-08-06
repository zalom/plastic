# encoding: UTF-8
# frozen_string_literal: true

require "yaml"
require "json"

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
  #   global store (<plastic_home>/store)          -> "plastic-global"
  #   project store (<.../projects/<slug>/store)   -> "plastic-<slug>"
  #   roadmaps dir (sibling of either store above)  -> the sibling store's
  #                                                    collection name, suffixed "-roadmaps"
  # Slug is resolved from projects.yml by matching the project path; falls back
  # to the directory's parent name when no registry match exists.
  def collection_name(store_dir, plastic_home:)
    store_dir = File.expand_path(store_dir)
    global_store = File.expand_path(File.join(plastic_home, "store"))
    return "plastic-global" if store_dir == global_store

    if File.basename(store_dir) == "roadmaps"
      sibling_store = File.join(File.dirname(store_dir), "store")
      return "#{collection_name(sibling_store, plastic_home: plastic_home)}-roadmaps"
    end

    slug = slug_for_store(store_dir, plastic_home: plastic_home)
    "plastic-#{slug}"
  end

  # Every store Plastic knows about: the global store plus each registered
  # project store, plus a roadmap-companion entry per tier when that tier's
  # sibling `roadmaps/` directory exists on disk (intent 135). Returns
  # [{collection:, dir:}, ...].
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

    stores.flat_map do |s|
      roadmaps_dir = File.join(File.dirname(s[:dir]), "roadmaps")
      next [s] unless Dir.exist?(roadmaps_dir)
      [s, { collection: "#{s[:collection]}-roadmaps", dir: roadmaps_dir }]
    end
  end

  # Register a store directory as a collection. Idempotent: re-running is safe.
  # `qmd collection add` exits non-zero when the collection already exists, so we
  # check the collection list first and treat an existing collection as success.
  # No-op when qmd is absent. (`qmd context add` attaches a summary to a document
  # path, not a collection-level description, so it is not used here.)
  def register(collection:, dir:, runner: default_runner, detector: method(:detect))
    return skip_result unless detector.call
    return { ran: true, ok: true, output: "exists" } if list_collections(runner).include?(collection)
    out, ok = runner.call(["collection", "add", dir, "--name", collection])
    { ran: true, ok: ok, output: out.to_s.strip }
  end

  # Re-index a single collection: refresh the corpus then its embeddings.
  # Scoped embed (-c) keeps delivery-time reindex fast. No-op when qmd absent.
  def reindex(collection:, runner: default_runner, detector: method(:detect))
    return skip_result unless detector.call
    _o1, ok1 = runner.call(["update"])
    _o2, ok2 = runner.call(["embed", "-c", collection])
    { ran: true, ok: (ok1 && ok2) }
  end

  # Non-blocking reindex for the completion path. QMD has no incremental reindex
  # (`qmd update` is a full rescan, `qmd embed -c` re-embeds the whole collection,
  # ~2 min), so running it inline would block the agent's turn; spawning detached
  # returns immediately. No-op when qmd absent. Spawner/detector are injected so
  # tests assert behavior with no real qmd and no real spawned process.
  def reindex_async(collection:, detector: method(:detect), spawner: method(:default_async_spawner))
    return skip_result unless detector.call
    pid = spawner.call(collection)
    { ran: true, async: true, pid: pid }
  end

  # Default spawner: launch `qmd update && qmd embed -c <collection>` detached and
  # non-blocking, discarding output, then detach so it never blocks the turn.
  def default_async_spawner(collection)
    require "shellwords"
    cmd = "qmd update && qmd embed -c #{Shellwords.escape(collection)}"
    pid = Process.spawn(cmd, out: File::NULL, err: File::NULL, pgroup: true)
    Process.detach(pid)
    pid
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

  # Read-only BM25 search over one or more collections. Returns hits sorted by
  # score (desc), filtered by min_score, capped at limit:
  #   [{ score: Float, file: String, line: Integer|nil, title: String, snippet: String }, ...]
  # No-ops to [] when qmd is absent or the query is blank. Uses `qmd search --json`
  # (BM25, no embeddings / no model downloads). Pure via the injected runner.
  def search(query, collections:, limit: 3, min_score: 0.5, runner: default_runner, detector: method(:detect))
    return [] unless detector.call
    q = query.to_s.strip
    return [] if q.empty? || Array(collections).empty?

    args = ["search", q]
    Array(collections).each { |c| args.concat(["-c", c]) }
    args << "--json"

    out, ok = runner.call(args)
    return [] unless ok && out && !out.strip.empty?

    parsed = begin
      JSON.parse(out)
    rescue StandardError
      return []
    end
    return [] unless parsed.is_a?(Array)

    parsed.filter_map do |h|
      next unless h.is_a?(Hash)
      score = h["score"].to_f
      next if score < min_score
      { score: score, file: h["file"].to_s, line: h["line"],
        title: h["title"].to_s, snippet: h["snippet"].to_s }
    end.sort_by { |h| -h[:score] }.first(limit)
  end

  # Which collections to search for a given working directory: the matched
  # project's collection plus plastic-global, or just plastic-global when the
  # CWD is not inside any registered project. Project match = CWD equals the
  # registered path or is nested under it.
  #
  # Each collection's roadmap companion (intent 135) is appended right after it
  # when actually registered (checked via the injected runner's `collection
  # list`), because `qmd search -c <unregistered-collection>` hard-fails the
  # whole call, so an unregistered companion must never be added blindly.
  def collections_for_cwd(cwd, plastic_home:, runner: default_runner, detector: method(:detect))
    cwd = File.expand_path(cwd)
    projects = load_projects(plastic_home)
    slug, = projects.find do |_s, info|
      path = info.is_a?(Hash) ? info["path"] : nil
      next false unless path
      root = File.expand_path(path)
      cwd == root || cwd.start_with?(root + File::SEPARATOR)
    end

    base = slug ? ["plastic-#{slug}", "plastic-global"] : ["plastic-global"]
    return base unless detector.call

    registered = list_collections(runner)
    base.flat_map do |c|
      roadmap = "#{c}-roadmaps"
      registered.include?(roadmap) ? [c, roadmap] : [c]
    end
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
