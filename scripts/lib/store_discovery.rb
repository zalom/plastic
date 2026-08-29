# encoding: UTF-8
# frozen_string_literal: true

require_relative "store_provisioning"

# StoreDiscovery: the single source of truth for "what stores exist" (intent 189).
#
# Two failure modes must both be avoided: missing a real store (a live cross-store ref
# into it gets classified dead and DELETED by rebuild-graph, the data-loss bug this module
# fixes) and silently treating a registered-but-unprovisioned project as an empty store (a
# different silent failure). So discovery is a SUPERSET: the global store (if it exists)
# plus every `projects/<slug>/store` directory that exists on disk, UNIONED with every slug
# registered in projects.yml. A registered slug with no store directory contributes no ids
# and is reported separately in `missing`, never silently dropped.
#
# Reuses StoreProvisioning.load_projects (rescues to {} so a malformed projects.yml never
# raises) instead of writing a third copy of that reader (a second copy already exists in
# QmdSync, out of scope here).
#
# Pure filesystem, dependency-injected: `discover` takes `plastic_home` as its only
# argument, performs no writes, no `system`/`spawn`, no network, no eval, no
# ENV/global-constant reads.
module StoreDiscovery
  module_function

  # Returns { stores: [ { key:, slug:, root:, store:, index: } ... ],
  #           missing: [ { slug:, project_dir: } ... ] }.
  #
  # `stores` entries: `key` is "global" or "project:<slug>" (the store_index/referer_store
  # key shape GraphRebuild and the doctor checks already use); `slug` is the bare token
  # form used in a cross-store ref ("global", "knowdb", "ai-agents-resources"); `root` is
  # the directory holding INDEX.md; `store` is the intents directory; `index` is the
  # INDEX.md path. Sorted by slug (global first) for deterministic output.
  #
  # `missing` lists every projects.yml slug with no `store/` directory on disk: legal
  # (the plastic-doctor provisioning section exists for exactly this state), reported so callers never
  # mistake it for a store with zero intents.
  def discover(plastic_home)
    stores = []
    missing = []

    global_store = File.join(plastic_home, "store")
    if File.directory?(global_store)
      stores << { key: "global", slug: "global", root: plastic_home,
                  store: global_store, index: File.join(plastic_home, "INDEX.md") }
    end

    registered = StoreProvisioning.load_projects(plastic_home) # { slug => info }, {} on error/absence
    projects_root = File.join(plastic_home, "projects")
    on_disk = File.directory?(projects_root) ? Dir.children(projects_root).reject { |e| e.start_with?(".") } : []

    all_slugs = (registered.keys + on_disk).uniq.sort

    all_slugs.each do |slug|
      root = File.join(projects_root, slug)
      store_dir = File.join(root, "store")
      if File.directory?(store_dir)
        stores << { key: "project:#{slug}", slug: slug, root: root,
                    store: store_dir, index: File.join(root, "INDEX.md") }
      elsif registered.key?(slug)
        missing << { slug: slug, project_dir: root }
      end
      # else: an on-disk directory with no store/ and no projects.yml entry (a junk dir,
      # e.g. a stale path-as-slug from a past bug). Silently excluded, exactly as doctor's
      # existing disk scan already does: it is neither a store nor a registered project.
    end

    { stores: stores, missing: missing }
  end

  # Convenience: just the known store SLUGS (the token form used in a cross-store ref),
  # for IntentValidator's injected known-store check (ACTION_7). "global" is included
  # when the global store exists.
  def known_slugs(plastic_home)
    discover(plastic_home)[:stores].map { |s| s[:slug] }
  end
end
