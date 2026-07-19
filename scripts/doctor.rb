#!/usr/bin/env ruby
# encoding: UTF-8
# frozen_string_literal: true

# Plastic doctor — diagnostic engine that checks a Plastic installation for health issues.
# Usage: ruby ~/.plastic/scripts/doctor.rb [--agent claude|codex|hermes] [--help]
#
# Output: JSON to stdout. Warnings/errors to stderr.
# Exit codes: 0 (all pass), 1 (warnings only), 2 (failures present)
# Read-only — never modifies files.

require "json"
require "yaml"
require "time"
require "date"
require "digest"
require "rubygems"

require_relative "lib/qmd_sync"
require_relative "lib/intent_validator"
require_relative "lib/graph_rebuild"
require_relative "lib/store_discovery"
require_relative "lib/links_projection"
require_relative "lib/links_section"
require_relative "lib/hook_registry"
require_relative "lib/lock"
require_relative "lib/bridge"
require_relative "lib/agent_models"
require_relative "lib/legacy_bookend_amnesty"
require_relative "lib/skill_lint"
require_relative "lib/config_asks"
require_relative "lib/power_tools"

# Diagnostic engine, instantiable with an injected store/agent map so tests can
# run it hermetically (no eval, no global-constant rewriting).
class Doctor
  DEFAULT_PLASTIC_HOME = File.join(Dir.home, ".plastic")

  DEFAULT_AGENTS = {
    "claude" => { name: "Claude Code", dir: File.join(Dir.home, ".claude") },
    "codex"  => { name: "Codex CLI",   dir: File.join(Dir.home, ".agents"),
                  home_dir: File.join(Dir.home, ".codex") },
    "hermes" => { name: "Hermes",      dir: File.join(Dir.home, ".hermes") },
  }.freeze

  REQUIRED_INDEX_SECTIONS = ["## Active", "## Future", "## Clusters", "## Abandoned", "## Completed"].freeze

  # Single source of truth for the required-field list lives in IntentValidator
  # (intent 60). Alias it here so the two can never drift.
  REQUIRED_FRONTMATTER_FIELDS = IntentValidator::REQUIRED_FIELDS

  # Single source of truth for the pre-161 legacy Done-bookend amnesty list
  # lives in LegacyBookendAmnesty (intent 170a). Alias it here so the two can
  # never drift.
  LEGACY_BOOKEND_AMNESTY = LegacyBookendAmnesty::LIST

  CLAUDE_HOOK_EVENTS = %w[SessionStart PreCompact PostToolUse UserPromptSubmit].freeze

  # Launchers the installer places in the agent's hooks dir that are NOT hooks
  # (intent 204): plastic-statusline is the settings["statusLine"] command, wired
  # outside HookRegistry.events entirely, so it must be excluded from the
  # orphan-launcher scan below or a correct install would report a false orphan.
  CLAUDE_NON_HOOK_LAUNCHERS = %w[plastic-statusline].freeze

  REQUIRED_SCRIPTS = %w[
    folgezettel-id
    read-config
    hook-session-start
    hook-continue
    hook-future-intent-check
    hook-gate-check
    validate-intent
    doctor.rb
  ].freeze

  # The apply_patch PreToolUse veto only fires from Codex v0.123.0 onward
  # (PR #18391, "emit hooks for apply_patch edits"). Below it the veto
  # silently no-ops (intent 184).
  CODEX_HOOKS_FLOOR = "0.123.0"

  attr_reader :plastic_home, :agents

  # Testable shell-out default, mirroring QmdSync.default_runner: a real
  # Open3.capture3 call in production, swappable for a fake in tests so no
  # test needs a real codex binary or a PATH mutation.
  def self.default_runner
    lambda do |args|
      require "open3"
      out, _err, status = Open3.capture3("codex", *args)
      [out, status.success?]
    rescue Errno::ENOENT
      ["", false] # codex not on PATH: undetectable, fail open
    end
  end

  def initialize(plastic_home: DEFAULT_PLASTIC_HOME, agents: DEFAULT_AGENTS,
                  bookend_amnesty: LEGACY_BOOKEND_AMNESTY, runner: Doctor.default_runner)
    @plastic_home = plastic_home
    @agents = agents
    @bookend_amnesty = bookend_amnesty
    @runner = runner
  end

  # --- Flag parsing ---

  def parse_args(argv)
    agent = "claude"
    help = false
    core = false
    # store flag representation:
    #   nil        — --store not given
    #   :all       — --store with no value (check every store)
    #   :global    — --store global
    #   "<slug>"   — --store <slug> (a single project)
    store = nil

    i = 0
    while i < argv.length
      case argv[i]
      when "--agent"
        if argv[i + 1] && agents.key?(argv[i + 1])
          agent = argv[i + 1]
          i += 2
        else
          $stderr.puts "Error: --agent requires one of: #{agents.keys.join(", ")}"
          exit 2
        end
      when "--core"
        core = true
        i += 1
      when "--store"
        nxt = argv[i + 1]
        if nxt && !nxt.start_with?("-")
          store = (nxt == "global") ? :global : nxt
          i += 2
        else
          store = :all
          i += 1
        end
      when "--help", "-h"
        help = true
        i += 1
      else
        i += 1
      end
    end

    { agent: agent, help: help, core: core, store: store }
  end

  def show_help
    $stderr.puts <<~HELP

      plastic doctor — diagnose Plastic installation health

      Usage:
        ruby ~/.plastic/scripts/doctor.rb [options]

      Options:
        --agent NAME    Agent to check: claude (default), codex, hermes
        --core          Binary core sync check: verifies agent registration, core
                        files, and that every manifest-tracked file matches its
                        recorded SHA256. Exits 0 (pass) or 2 (fail); never warn.
        --store [WHICH] Run only the store/conventions checks. WHICH may be:
                        global (global store only), a project slug (that project
                        only), or omitted (all stores). 3-state pass/warn/fail.
        -h, --help      Show this help

      Output:
        JSON to stdout with check results.
        Exit 0 = all pass, 1 = warnings only, 2 = failures present.

    HELP
  end

  # --- Utility helpers ---

  def read_version
    version_path = File.join(plastic_home, "VERSION")
    return nil unless File.exist?(version_path)

    File.read(version_path).strip
  end

  def read_json_safe(path)
    return nil unless File.exist?(path)

    JSON.parse(File.read(path))
  rescue JSON::ParserError
    content = File.read(path).gsub(%r{//[^\n]*}, "").gsub(/,(\s*[}\]])/, '\1')
    JSON.parse(content)
  rescue
    nil
  end

  def load_yaml_safe(path)
    return nil unless File.exist?(path)

    YAML.safe_load(File.read(path)) || {}
  rescue => e
    $stderr.puts "Warning: failed to parse #{path}: #{e.message}"
    nil
  end

  def tilde(path)
    path.sub(Dir.home, "~")
  end

  def check(category:, name:, status:, message:, details: [], fixable: false, fix_hint: nil)
    result = {
      category: category,
      name: name,
      status: status,
      message: message,
      details: details,
      fixable: fixable,
    }
    result[:fix_hint] = fix_hint if fix_hint
    result
  end

  # --- Parse frontmatter from an intent markdown file ---

  def parse_frontmatter(path)
    return nil unless File.exist?(path)

    content = File.read(path)
    return nil unless content.start_with?("---")

    parts = content.split("---", 3)
    return nil if parts.length < 3

    # created: dates parse as Date objects, which safe_load rejects by default —
    # permit Date/Time so valid frontmatter isn't misreported as missing.
    YAML.safe_load(parts[1], permitted_classes: [Date, Time]) || {}
  rescue
    nil
  end

  # --- Collect all intent directories (global + project stores) ---

  # Child directories of a store, excluding dotfiles/dot-directories
  # (e.g. .obsidian, .git) which are tooling artifacts, not intents.
  def store_intent_dirs(store)
    Dir.children(store).reject { |e| e.start_with?(".") }.select do |e|
      File.directory?(File.join(store, e))
    end
  end

  # Single source of truth for "what stores exist" (intent 189), shared with
  # rebuild-graph, project-links, and new-intent via StoreDiscovery. Memoized: one Doctor
  # instance runs many checks against the same plastic_home in a single pass.
  def store_discovery
    @store_discovery ||= StoreDiscovery.discover(plastic_home)
  end

  def all_intent_dirs
    dirs = []
    store_discovery[:stores].each do |s|
      store_intent_dirs(s[:store]).each do |entry|
        full = File.join(s[:store], entry)
        dirs << { path: full, name: entry, scope: s[:key] }
      end
    end
    dirs
  end

  # A store_index Hash seeded with EVERY store StoreDiscovery reports, mapping a
  # store with zero intents to [] rather than leaving its key absent. Mirrors
  # RebuildGraph#run and ProjectLinks#run, which both set `store_index[key] =
  # nodes.keys` for every discovered store (empty array for an empty store). Without
  # this seed, a store_index built only from intents that parse has no key for a
  # freshly provisioned, still-empty store, so GraphRebuild.classify calls it
  # :unknown_store instead of :dead, disagreeing with the repair tools about the
  # same ref (intent 189 review, finding 1).
  def seeded_store_index
    idx = Hash.new { |h, k| h[k] = [] }
    store_discovery[:stores].each { |s| idx[s[:key]] }
    idx
  end

  # --- Check category 1: Global store ---

  def check_global_store
    checks = []

    index_path = File.join(plastic_home, "INDEX.md")

    # index_exists
    if File.exist?(index_path)
      checks << check(
        category: "global_store", name: "index_exists", status: "pass",
        message: "INDEX.md exists"
      )
    else
      checks << check(
        category: "global_store", name: "index_exists", status: "fail",
        message: "INDEX.md not found at #{tilde(index_path)}",
        fixable: true, fix_hint: "Run the Plastic installer to bootstrap the store"
      )
      return checks # Can't check sections/references without INDEX.md
    end

    # index_sections
    content = File.read(index_path)
    missing_sections = REQUIRED_INDEX_SECTIONS.reject { |s| content.include?(s) }

    if missing_sections.empty?
      checks << check(
        category: "global_store", name: "index_sections", status: "pass",
        message: "INDEX.md has all 5 required sections"
      )
    else
      checks << check(
        category: "global_store", name: "index_sections", status: "fail",
        message: "INDEX.md missing #{missing_sections.size} required section(s)",
        details: missing_sections,
        fixable: true, fix_hint: "Add missing sections to INDEX.md"
      )
    end

    # orphaned_intents — directories in store/ not referenced in INDEX.md
    store_dir = File.join(plastic_home, "store")
    if File.directory?(store_dir)
      intent_dirs = store_intent_dirs(store_dir)
      orphans = intent_dirs.reject { |d| content.include?("store/#{d}") }

      if orphans.empty?
        checks << check(
          category: "global_store", name: "orphaned_intents", status: "pass",
          message: "No orphaned intent directories"
        )
      else
        checks << check(
          category: "global_store", name: "orphaned_intents", status: "warn",
          message: "#{orphans.size} intent director#{orphans.size == 1 ? "y" : "ies"} not referenced in INDEX.md",
          details: orphans.map { |d| "store/#{d}" },
          fixable: true, fix_hint: "Add missing intents to INDEX.md or remove orphaned directories"
        )
      end
    end

    # ghost_references — paths in INDEX.md pointing to non-existent directories
    store_refs = content.scan(%r{store/[\w][\w-]*(?:/[\w][\w.-]*)*/?\b}).uniq
    # Normalize: extract just the store/ID--slug portion
    store_paths = content.scan(%r{store/\S+}).map { |ref| ref.gsub(/[)\]>].*/, "").chomp("/") }.uniq

    ghosts = store_paths.select do |ref|
      full_path = File.join(plastic_home, ref)
      !File.exist?(full_path) && !File.directory?(full_path)
    end

    if ghosts.empty?
      checks << check(
        category: "global_store", name: "ghost_references", status: "pass",
        message: "No ghost references in INDEX.md"
      )
    else
      checks << check(
        category: "global_store", name: "ghost_references", status: "warn",
        message: "#{ghosts.size} path(s) in INDEX.md point to non-existent locations",
        details: ghosts,
        fixable: true, fix_hint: "Remove or fix broken references in INDEX.md"
      )
    end

    checks
  end

  # --- Check category: global store availability (core-only, D1) ---
  #
  # Narrow, core-appropriate version of check_global_store: presence/readability only, zero
  # content scanning. check_global_store (above) is store/full-scope and includes
  # orphaned_intents / ghost_references, both explicitly forbidden at core by D1.
  def check_global_store_available
    checks = []

    if File.directory?(plastic_home)
      checks << check(
        category: "global_store", name: "global_store_reachable", status: "pass",
        message: "Global store directory reachable at #{tilde(plastic_home)}"
      )
    else
      checks << check(
        category: "global_store", name: "global_store_reachable", status: "fail",
        message: "Global store directory not found at #{tilde(plastic_home)}",
        fixable: true, fix_hint: "Run the Plastic installer to bootstrap the store"
      )
      return checks
    end

    index_path = File.join(plastic_home, "INDEX.md")
    if File.exist?(index_path)
      checks << check(
        category: "global_store", name: "global_index_reachable", status: "pass",
        message: "INDEX.md exists"
      )
    else
      checks << check(
        category: "global_store", name: "global_index_reachable", status: "fail",
        message: "INDEX.md not found at #{tilde(index_path)}",
        fixable: true, fix_hint: "Run the Plastic installer to bootstrap the store"
      )
    end

    checks
  end

  # --- Check category 2: Conventions ---

  # When `scopes` is a non-nil Array of scope strings (e.g. ["global"] or
  # ["project:plastic"]), only intents whose :scope is in that list are checked.
  # When nil (the default, used by the full run), every intent is checked.
  def check_conventions(scopes: nil)
    checks = []

    intent_dirs = all_intent_dirs
    intent_dirs = intent_dirs.select { |d| scopes.include?(d[:scope]) } unless scopes.nil?
    dirname_pattern = /^\w+--[\w-]+$/

    # intent_dirname
    bad_dirnames = intent_dirs.reject { |d| d[:name].match?(dirname_pattern) }

    if bad_dirnames.empty?
      checks << check(
        category: "conventions", name: "intent_dirname", status: "pass",
        message: "All #{intent_dirs.size} intent directories follow {ID}--{slug} format"
      )
    else
      checks << check(
        category: "conventions", name: "intent_dirname", status: "warn",
        message: "#{bad_dirnames.size} intent director#{bad_dirnames.size == 1 ? "y doesn't" : "ies don't"} follow {ID}--{slug} format",
        details: bad_dirnames.map { |d| "#{tilde(d[:path])} (#{d[:scope]})" },
        fixable: true, fix_hint: "Rename directories to {ID}--{slug} format"
      )
    end

    # intent_filename — primary file inside directory matches {ID}--{slug}.md
    bad_filenames = []
    intent_dirs.each do |d|
      expected_file = "#{d[:name]}.md"
      expected_path = File.join(d[:path], expected_file)
      unless File.exist?(expected_path)
        bad_filenames << { dir: d, expected: expected_file }
      end
    end

    if bad_filenames.empty?
      checks << check(
        category: "conventions", name: "intent_filename", status: "pass",
        message: "All intent directories have matching {ID}--{slug}.md files"
      )
    else
      checks << check(
        category: "conventions", name: "intent_filename", status: "warn",
        message: "#{bad_filenames.size} intent director#{bad_filenames.size == 1 ? "y" : "ies"} missing primary .md file",
        details: bad_filenames.map { |b| "#{tilde(b[:dir][:path])} — expected #{b[:expected]}" },
        fixable: true, fix_hint: "Create or rename the primary .md file to match the directory name"
      )
    end

    # frontmatter_fields
    bad_frontmatter = []
    intent_dirs.each do |d|
      md_path = File.join(d[:path], "#{d[:name]}.md")
      next unless File.exist?(md_path)

      fm = parse_frontmatter(md_path)
      if fm.nil?
        bad_frontmatter << { dir: tilde(d[:path]), missing: ["(no frontmatter found)"] }
        next
      end

      # Delegate missing-field detection to the single source of truth.
      missing = IntentValidator.validate_frontmatter(fm)[:missing]
      bad_frontmatter << { dir: tilde(d[:path]), missing: missing } unless missing.empty?
    end

    if bad_frontmatter.empty?
      checks << check(
        category: "conventions", name: "frontmatter_fields", status: "pass",
        message: "All intent files have required frontmatter fields"
      )
    else
      checks << check(
        category: "conventions", name: "frontmatter_fields", status: "warn",
        message: "#{bad_frontmatter.size} intent file(s) missing required frontmatter fields",
        details: bad_frontmatter.map { |b| "#{b[:dir]}: missing #{b[:missing].join(", ")}" },
        fixable: true,
        fix_hint: "Inject the missing required frontmatter field(s) (e.g. chain: []) without disturbing other keys"
      )
    end

    # frontmatter_valid — per-intent frontmatter shape (sources/chain are
    # well-formed arrays of id strings). Delegates to IntentValidator so the
    # born-complete contract is defined in exactly one place. Read-only: shape
    # repair is not a single-field inject, so this check is not fixable here.
    known_stores = store_discovery[:stores].map { |s| s[:slug] }
    malformed = []
    intent_dirs.each do |d|
      md_path = File.join(d[:path], "#{d[:name]}.md")
      next unless File.exist?(md_path)

      result = IntentValidator.validate_frontmatter(parse_frontmatter(md_path), known_stores: known_stores)
      shape_errors = result[:errors].select { |e| e.include?("must be an array") || e.include?("invalid id") }
      malformed << { dir: tilde(d[:path]), errors: shape_errors } unless shape_errors.empty?
    end

    if malformed.empty?
      checks << check(
        category: "conventions", name: "frontmatter_valid", status: "pass",
        message: "All intent frontmatter is well-formed"
      )
    else
      checks << check(
        category: "conventions", name: "frontmatter_valid", status: "warn",
        message: "#{malformed.size} intent file(s) have malformed sources/chain",
        details: malformed.map { |m| "#{m[:dir]}: #{m[:errors].join(", ")}" },
        fixable: false
      )
    end

    # section_structure — per-intent top-level `##` section set. Reuses
    # IntentValidator::SANCTIONED_SECTIONS / validate_sections so the sanctioned
    # set is defined in exactly one place (shared with the create gate and the
    # validate-intent CLI). Read-only diagnostic: unknown or missing sections are
    # not auto-fixable here.
    bad_sections = []
    intent_dirs.each do |d|
      md_path = File.join(d[:path], "#{d[:name]}.md")
      next unless File.exist?(md_path)

      body = IntentValidator.body_of(File.read(md_path))
      result = IntentValidator.validate_sections(body)
      next if result[:ok]

      issues = []
      issues.concat(result[:unknown].map { |h| "unknown #{h}" })
      issues.concat(result[:missing].map { |s| "missing #{s}" })
      bad_sections << { dir: tilde(d[:path]), issues: issues }
    end

    if bad_sections.empty?
      checks << check(
        category: "conventions", name: "section_structure", status: "pass",
        message: "All intent files have the sanctioned ## section structure"
      )
    else
      checks << check(
        category: "conventions", name: "section_structure", status: "warn",
        message: "#{bad_sections.size} intent file(s) have non-sanctioned ## sections",
        details: bad_sections.map { |b| "#{b[:dir]}: #{b[:issues].join(", ")}" },
        fixable: true,
        fix_hint: "Dispatch plastic-store-curating to relocate each unsanctioned section into the " \
                  "intent's revisions.md via move-and-record (a missing required section is restored " \
                  "or reprojected instead); see PLASTIC.md > Structural maintenance and revisions.md"
      )
    end

    # graph_invariants — cross-intent I1/I3/I4 checks (intent 68). I1/I3/I4 are
    # defined within a single store's id space (bare ids resolve within the same
    # store), so build the `nodes` map per scope and run validate_graph per scope.
    # I2 asymmetry (a relational chain entry with no reciprocal sources) is NEVER
    # flagged: validate_graph does not compute it.
    checks.concat(graph_invariant_checks(intent_dirs))

    # cross_store_resolution — RESOLVES (not just shape-checks) every cross-store
    # `store:id` ref against the FULL store family via the relocation map
    # (relocation consulted first), closing the shape-only gap i1/i3/i4 leave open.
    # Resolution always spans all stores even under `--store` scoping; only the
    # REPORTED findings are filtered to refs originating in the scoped store(s).
    checks << cross_store_resolution_check(scopes: scopes)

    # graph_links_projection — the `## Links` section of every intent must EQUAL its
    # canonical I5 frontmatter projection (intent 72), in BOTH set membership AND
    # ordering (sources first, then chain). Recomputes the projection from each
    # intent's sources/chain + the on-disk basenames using the SAME resolver the
    # scripts/project-links tool uses, so the two can never diverge. Resolution
    # spans all stores; only the REPORTED findings are filtered to the scoped store.
    checks << links_projection_check(scopes: scopes)

    checks
  end

  # --- Check: the three done-signals agree + stalled completion (intent 93) ---
  #
  # "Done" is one law with three signals that MUST agree: INDEX
  # `## Completed`/`## Abandoned` is the single canonical terminal marker;
  # `outcome.md` is the "deliverable exists" signal (real, non-placeholder, with a
  # `disposition:` header); the savepoint `Done` line is the audit echo. INDEX
  # wins on conflict. This check flags any disagreement, and separately surfaces a
  # "stalled completion": an intent that is terminal in INDEX but whose End tail
  # never released its `delivery.lock` (the post-done window never closed). Read
  # only, dependency-light: it uses INDEX parsing, file presence, the placeholder
  # sentinel, and `Lock.fresh?` — no new lock, no 111 lock-liveness surface.

  # For one store's INDEX.md, map each referenced intent directory name to the
  # `## ...` section(s) it appears under: { "<id>--<slug>" => ["Active", ...] }.
  def index_sections_by_dir(index_path)
    sections = Hash.new { |h, k| h[k] = [] }
    return sections unless File.exist?(index_path)

    current = nil
    File.foreach(index_path) do |line|
      if (m = line.match(/^##\s+(.+?)\s*$/))
        current = m[1]
        next
      end
      next unless current

      line.scan(%r{store/([\w][\w.-]*?)(?:/|\))}) do |(dirname)|
        sections[dirname] << current unless sections[dirname].include?(current)
      end
    end
    sections
  end

  # Stores to reconcile: the global store plus each project store, filtered by
  # `scopes` (nil = all) exactly like check_conventions.
  def done_signal_stores(scopes)
    stores = []

    if scopes.nil? || scopes.include?("global")
      stores << {
        scope: "global",
        index: File.join(plastic_home, "INDEX.md"),
        store_dir: File.join(plastic_home, "store"),
      }
    end

    projects_root = File.join(plastic_home, "projects")
    if File.directory?(projects_root)
      Dir.children(projects_root).sort.each do |project|
        scope = "project:#{project}"
        next unless scopes.nil? || scopes.include?(scope)

        store_dir = File.join(projects_root, project, "store")
        next unless File.directory?(store_dir)

        stores << {
          scope: scope,
          index: File.join(projects_root, project, "INDEX.md"),
          store_dir: store_dir,
        }
      end
    end

    stores
  end

  def check_done_signals(scopes: nil)
    conflicts = [] # canonical INDEX-wins disagreement (fail)
    gaps = []      # terminal completeness gaps on immutable/legacy history (warn)
    stalled = []   # terminal but End tail unfinished (warn)
    phantoms = []  # savepoint.md line(s) disk evidence contradicts (warn, never fail; intent 134)

    done_signal_stores(scopes).each do |store|
      index_sections_by_dir(store[:index]).each do |dirname, in_sections|
        dir = File.join(store[:store_dir], dirname)
        next unless File.directory?(dir)

        terminal = (in_sections & ["Completed", "Abandoned"]).any?
        active = in_sections.include?("Active") && !terminal
        outcome = File.join(dir, "outcome.md")
        outcome_real = Bridge.stage_file_present?(outcome)
        label = "#{store[:scope]} store/#{dirname}"

        # HARD conflict: the deliverable exists but INDEX still says Active. This
        # is the one true INDEX-wins disagreement, so it stays a fail.
        if active && outcome_real
          conflicts << "#{label}: outcome.md is real but the intent is still under ## Active " \
                       "(INDEX is canonical — move it to its terminal section or revert outcome.md)"
        end

        # Savepoint truthfulness (advisory, never fail; intent 134): a line the disk contradicts
        # (a phantom milestone, a duplicate pair, or a state line with an absent prerequisite).
        # Live intents auto-rebuild via plastic-intent-savepoint; terminal intents are immutable,
        # so a phantom there is report-only. Composition with intent 170a: a pre-161 legacy intent
        # on the frozen bookend amnesty is grandfathered here too. Its immutable history carries
        # known pre-convention drift (the same class the audit-echo gap forgives), so it must not
        # resurface through this advisory. The suppression is scope-qualified exactly like the
        # audit-echo amnesty; every live intent and every non-amnestied terminal still fires.
        phantom_lines = Bridge.savepoint_phantom_lines(dir)
        phantom_id = dirname.split("--", 2).first
        phantom_amnestied = terminal && @bookend_amnesty.fetch(store[:scope], []).include?(phantom_id)
        if phantom_lines.any? && !phantom_amnestied
          detail = phantom_lines.map { |line, reason| "#{line} (#{reason})" }.join("; ")
          scope_note = terminal ? "terminal in INDEX, report-only (immutable history)" : "live intent, auto-rebuildable"
          phantoms << "#{label}: #{phantom_lines.size} phantom savepoint line(s) contradicted by " \
                      "disk, #{scope_note}: #{detail}"
        end

        # Completeness gap (warn, not fail): a terminal intent whose outcome.md is
        # missing/placeholder. Legacy terminal intents predate this convention and
        # are immutable, so this is advisory, never breakage.
        if terminal && !outcome_real
          state = File.exist?(outcome) ? "still a placeholder" : "missing"
          gaps << "#{label}: terminal in INDEX but outcome.md is #{state} " \
                  "(author outcome.md with the disposition header)"
        end

        next unless terminal

        # Audit echo (weakest signal, D1): the savepoint should carry a
        # `Done delivered|abandoned` line. Missing on legacy history -> advisory
        # gap, unless the (scope, id) is on the frozen pre-161 amnesty list
        # (intent 170a). The amnesty is scope-qualified: an id on the list for
        # one scope does not grandfather the same id in another scope.
        savepoint = File.join(dir, "savepoint.md")
        if File.exist?(savepoint) && File.read(savepoint) !~ /\bDone\b.*\b(delivered|abandoned)\b/
          id = dirname.split("--", 2).first
          amnestied = @bookend_amnesty.fetch(store[:scope], []).include?(id)
          unless amnestied
            gaps << "#{label}: terminal in INDEX but savepoint.md has no " \
                    "`Done delivered|abandoned` line (audit echo missing)"
          end
        end

        # Stalled completion: the End tail never released the delivery lock, so the
        # post-done window `[INDEX terminal -> Lock.release]` never closed.
        if File.exist?(Lock.path(dir))
          note = Lock.fresh?(dir) ? "delivery.lock still present (post-done window not closed)"
                                  : "delivery.lock is present and STALE"
          stalled << "#{label}: #{note} — the End tail did not finish"
        end
      end
    end

    checks = []

    # signals_agree: only the canonical INDEX-wins conflict is a hard fail, so
    # `doctor` never goes red on immutable legacy terminal intents.
    if conflicts.empty?
      checks << check(
        category: "done_signals", name: "signals_agree", status: "pass",
        message: "No done-signal conflicts (no intent has a real outcome.md while still Active)"
      )
    else
      checks << check(
        category: "done_signals", name: "signals_agree", status: "fail",
        message: "#{conflicts.size} done-signal conflict#{conflicts.size == 1 ? "" : "s"} " \
                 "(INDEX ## Completed/## Abandoned is canonical; a real outcome.md must not stay Active)",
        details: conflicts, fixable: true,
        fix_hint: "Reconcile to INDEX (canonical): move the intent to its terminal section, or revert " \
                  "outcome.md to a placeholder. Deliverable-exists but still-Active is the one done-signal " \
                  "state that must never persist."
      )
    end

    # signals_complete: terminal completeness gaps are advisory (warn), because
    # completed intents are immutable and legacy history predates this convention.
    if gaps.empty?
      checks << check(
        category: "done_signals", name: "signals_complete", status: "pass",
        message: "Every terminal intent carries a real outcome.md and a Done savepoint echo"
      )
    else
      checks << check(
        category: "done_signals", name: "signals_complete", status: "warn",
        message: "#{gaps.size} terminal completeness gap#{gaps.size == 1 ? "" : "s"} " \
                 "(outcome.md or the savepoint Done echo is missing; advisory on immutable history)",
        details: gaps, fixable: true,
        fix_hint: "For live terminals, author a real outcome.md with the `disposition:` header via the " \
                  "completion/abandon path (plastic-auto or plastic-store-curating) and stamp the terminal " \
                  "savepoint. Legacy terminal intents are immutable, so pre-convention gaps stay advisory."
      )
    end

    if stalled.empty?
      checks << check(
        category: "done_signals", name: "stalled_completion", status: "pass",
        message: "No stalled completions (every terminal intent released its delivery lock)"
      )
    else
      checks << check(
        category: "done_signals", name: "stalled_completion", status: "warn",
        message: "#{stalled.size} stalled completion#{stalled.size == 1 ? "" : "s"} " \
                 "(terminal in INDEX but the End tail did not finish)",
        details: stalled, fixable: true,
        fix_hint: "Finish the End tail via stale-lock reclaim: run /plastic-doctor reclaim the lock, " \
                  "then complete the tail (Worktree.release -> Lock.release -> purge -> QMD reindex " \
                  "last). This FINISHES a completion; it is NOT a reactivation of a done intent."
      )
    end

    # savepoint_truthful: advisory only, never fails the run (intent 134). A phantom line on a
    # live intent auto-rebuilds; on terminal (immutable) history it stays report-only.
    if phantoms.empty?
      checks << check(
        category: "done_signals", name: "savepoint_truthful", status: "pass",
        message: "No savepoint.md lines are contradicted by disk (phantom-line check clean)"
      )
    else
      checks << check(
        category: "done_signals", name: "savepoint_truthful", status: "warn",
        message: "#{phantoms.size} intent#{phantoms.size == 1 ? "" : "s"} carry savepoint.md " \
                 "line(s) contradicted by disk (advisory; terminal history stays report-only)",
        details: phantoms, fixable: true,
        fix_hint: "For a live (Active) intent, run plastic-intent-savepoint to rebuild via " \
                  "Bridge.rebuild_savepoint. Terminal (Completed/Abandoned) intents are immutable: " \
                  "a phantom there stays advisory unless an explicit human grant authorizes the " \
                  "124a manual Done-bookend repair."
      )
    end

    checks
  end

  # Build the cross-store node maps (basename + label per store) + relocation map
  # from ALL stores, then for every intent compute its canonical `## Links`
  # projection and flag any whose ACTUAL `## Links` section differs (membership or
  # ordering drift), or whose projection raises UnresolvedRef. `scopes` (nil = full
  # run) filters only the REPORTED findings by origin scope.
  def links_projection_check(scopes: nil)
    all_dirs = all_intent_dirs

    store_index = seeded_store_index
    node_index = Hash.new { |h, k| h[k] = {} }
    intents = [] # { scope:, id:, sources:, chain:, path: }

    all_dirs.each do |d|
      md = File.join(d[:path], "#{d[:name]}.md")
      next unless File.exist?(md)

      fm = parse_frontmatter(md)
      next unless fm.is_a?(Hash) && fm["id"]

      id = fm["id"].to_s
      store_index[d[:scope]] << id
      node_index[d[:scope]][id] = { basename: d[:name], label: fm["intent"].to_s.strip }
      intents << {
        scope: d[:scope], id: id, path: md,
        sources: Array(fm["sources"]).map(&:to_s),
        chain: Array(fm["chain"]).map(&:to_s),
      }
    end

    relocation_map = GraphRebuild.build_relocation_map(cross_store_index_texts)

    findings = []
    intents.each do |node|
      next if scopes && !scopes.include?(node[:scope])

      resolve = ->(ref) do
        LinksProjection.resolve_ref_projection(
          ref, referer_store: node[:scope],
               relocation_map: relocation_map, store_index: store_index, node_index: node_index
        )
      end

      begin
        expected = LinksProjection.section(sources: node[:sources], chain: node[:chain], resolve: resolve)
        actual = actual_links_section(node[:path])
      rescue LinksProjection::UnresolvedRef => e
        findings << "#{node[:id]} ## Links projection failed: #{e.message}"
        next
      rescue LinksSection::AmbiguousLinks => e
        findings << "#{node[:id]} ## Links ambiguous: #{e.message}"
        next
      end

      next if actual == expected

      findings << "#{node[:id]} ## Links does not match its frontmatter projection (membership/ordering drift)"
    end

    graph_finding_check(
      "graph_links_projection", findings,
      "Every intent's ## Links equals its frontmatter projection (membership and ordering)",
      "Run scripts/project-links to regenerate the canonical ## Links sections. By default " \
      "it PRESERVES any line unbacked by frontmatter that still resolves to a real intent " \
      "(reported as an orphan candidate, never silently deleted); add the missing " \
      "sources/chain edge if the relationship is real, or pass --drop-unbacked-links to " \
      "delete an orphan candidate deliberately. Prefer `ruby scripts/maintenance-run --tool " \
      "project-links --intent <id> --apply` over running project-links directly: it detects " \
      "(never acquires) the target's delivery lock, requires a clean store working tree, and " \
      "commits the scoped change plus its revisions.md receipt as one merged operation " \
      "(PLASTIC.md > WORK vs MAINTENANCE)."
    )
  end

  # Extract a file's ACTUAL REAL `## Links` section text (FENCE-AWARE), normalized
  # to the canonical block shape the projection emits. Delegates to the shared
  # LinksSection.extract_section so the doctor check and the project-links tool
  # agree on the section location and never match a `## Links` heading inside an
  # example code fence. Returns "" when the section is absent (which differs from
  # any real projection, so a missing section is a finding).
  def actual_links_section(path)
    LinksSection.extract_section(IntentValidator.body_of(File.read(path)))
  end

  # Build the relocation map + cross-store store_index from ALL stores, then for
  # every intent's cross-store `sources`/`chain` ref resolve it and flag:
  #   - DEAD: the target resolves nowhere
  #   - RELOCATED-STALE: the ref points at an old location the relocation log has
  #     moved (the resolved location differs from the literal ref), e.g. the
  #     `global:24` id-reuse hazard that direct resolution would silently accept.
  # `scopes` (nil = full run) filters only the REPORTED findings by origin scope.
  def cross_store_resolution_check(scopes: nil)
    all_dirs = all_intent_dirs

    # Per-scope node maps + store_index over the WHOLE family.
    nodes_by_scope = Hash.new { |h, k| h[k] = {} }
    store_index = seeded_store_index
    all_dirs.each do |d|
      md = File.join(d[:path], "#{d[:name]}.md")
      next unless File.exist?(md)

      fm = parse_frontmatter(md)
      next unless fm.is_a?(Hash) && fm["id"]

      id = fm["id"].to_s
      store_index[d[:scope]] << id
      nodes_by_scope[d[:scope]][id] = {
        sources: Array(fm["sources"]).map(&:to_s),
        chain: Array(fm["chain"]).map(&:to_s),
      }
    end

    relocation_map = GraphRebuild.build_relocation_map(cross_store_index_texts)

    findings = []
    nodes_by_scope.each do |scope, nodes|
      next if scopes && !scopes.include?(scope)

      nodes.each do |id, edges|
        %i[sources chain].each do |field|
          edges[field].each do |ref|
            next unless ref.include?(":") # only cross-store refs are resolved here

            res = GraphRebuild.resolve_ref(ref, referer_store: scope,
                                                relocation_map: relocation_map,
                                                store_index: store_index)
            case res[:status]
            when :unknown_store
              findings << "#{id}.#{field} cross-store ref #{ref} names a store this scan does " \
                          "not recognize (#{res[:store]}); left untouched, verify store discovery"
            when :dead
              findings << "#{id}.#{field} cross-store ref #{ref} resolves to no intent (dead)"
            when :same_store
              findings << "#{id}.#{field} cross-store ref #{ref} is relocated-stale (now same-store #{res[:id]})"
            when :cross_store
              findings << "#{id}.#{field} cross-store ref #{ref} is relocated-stale (now #{res[:ref]})" if res[:ref] != ref
            end
          end
        end
      end
    end

    graph_finding_check(
      "graph_cross_store_resolution", findings,
      "Every cross-store sources/chain ref resolves to a live, current intent",
      "Run scripts/rebuild-graph to repoint/collapse/drop stale cross-store refs"
    )
  end

  # { store_key => INDEX.md text } for every store (global + all projects), for the
  # relocation-map builder. Sourced from the same StoreDiscovery list all_intent_dirs
  # uses, so the two can never enumerate a different set of stores.
  def cross_store_index_texts
    texts = {}
    store_discovery[:stores].each do |s|
      texts[s[:key]] = File.read(s[:index]) if File.exist?(s[:index])
    end
    texts
  end

  # Build a per-scope `nodes` map and surface IntentValidator.validate_graph
  # findings as warn-level checks. Scope-aware (the caller already filtered
  # `intent_dirs` by scope), so a `global` id is not falsely flagged as a dangler
  # when only a `project:` store is loaded, and vice versa.
  def graph_invariant_checks(intent_dirs)
    nodes_by_scope = Hash.new { |h, k| h[k] = {} }
    intent_dirs.each do |d|
      md_path = File.join(d[:path], "#{d[:name]}.md")
      next unless File.exist?(md_path)

      fm = parse_frontmatter(md_path)
      next unless fm.is_a?(Hash) && fm["id"]

      nodes_by_scope[d[:scope]][fm["id"].to_s] = {
        sources: Array(fm["sources"]).map(&:to_s),
        chain: Array(fm["chain"]).map(&:to_s),
      }
    end

    i1 = []
    i3 = []
    i4 = []
    nodes_by_scope.each_value do |nodes|
      findings = IntentValidator.validate_graph(nodes)
      i1.concat(findings[:i1])
      i3.concat(findings[:i3])
      i4.concat(findings[:i4])
    end

    checks = []
    checks << graph_finding_check(
      "graph_i1_reciprocity", i1,
      "Every sources edge has its reciprocal chain entry (I1)",
      "Run new-intent / the rebuild so each source intent's chain backlinks the child"
    )
    checks << graph_finding_check(
      "graph_i3_disjoint", i3,
      "No intent lists the same id in both sources and chain (I3)",
      "Remove the overlapping id from either sources or chain"
    )
    checks << graph_finding_check(
      "graph_i4_danglers", i4,
      "Every sources/chain id resolves to a real intent (I4)",
      "Dispatch plastic-store-curating to record the dangling sources/chain edge as a " \
      "broken-source/broken-chain move-and-record entry in the intent's revisions.md (see " \
      "PLASTIC.md > Structural maintenance and revisions.md), or restore the missing intent"
    )
    checks
  end

  # One graph check: pass when `findings` is empty, otherwise warn (never fail, so
  # an existing store does not turn red on a graph finding). I1/I4 are auto-fixable.
  def graph_finding_check(name, findings, pass_message, fix_hint)
    if findings.empty?
      check(category: "conventions", name: name, status: "pass", message: pass_message)
    else
      check(
        category: "conventions", name: name, status: "warn",
        message: "#{findings.size} #{name} violation(s)",
        details: findings,
        fixable: name != "graph_i3_disjoint",
        fix_hint: fix_hint
      )
    end
  end

  # --- Check category 3: Agent registration ---

  def check_agent_registration(agent_key)
    checks = []
    config = agents[agent_key]
    agent_dir = config[:dir]

    unless File.directory?(agent_dir)
      checks << check(
        category: "agent_registration", name: "agent_dir_exists", status: "fail",
        message: "Agent directory #{tilde(agent_dir)} not found — #{config[:name]} may not be installed",
        fixable: false
      )
      return checks
    end

    case agent_key
    when "claude"
      checks += check_claude_registration(agent_dir)
    when "codex"
      checks += check_codex_registration(agent_key, agent_dir)
    else
      checks += check_generic_agent_registration(agent_key, agent_dir)
    end

    checks
  end

  def check_claude_registration(agent_dir)
    checks = []
    hooks_dir = File.join(agent_dir, "hooks")

    # Derived from HookRegistry.events (intent 204), not a hand-kept list, so
    # every registered hook (all 15, including the enforcement gates) is checked.
    expected_launchers = HookRegistry.claude_launcher_names

    # hooks_exist
    missing_hooks = expected_launchers.reject { |h| File.exist?(File.join(hooks_dir, h)) }

    if missing_hooks.empty?
      checks << check(
        category: "agent_registration", name: "hooks_exist", status: "pass",
        message: "All #{expected_launchers.size} expected hook scripts exist"
      )
    else
      checks << check(
        category: "agent_registration", name: "hooks_exist", status: "fail",
        message: "#{missing_hooks.size} hook script(s) missing",
        details: missing_hooks.map { |h| "#{tilde(hooks_dir)}/#{h}" },
        fixable: true, fix_hint: "Re-run the Plastic installer: npx @zalom/plastic@latest --claude"
      )
    end

    # hooks_executable
    existing_hooks = expected_launchers
      .map { |h| File.join(hooks_dir, h) }
      .select { |p| File.exist?(p) }

    non_executable = existing_hooks.reject { |p| File.executable?(p) }

    if non_executable.empty?
      checks << check(
        category: "agent_registration", name: "hooks_executable", status: "pass",
        message: "All existing hook scripts are executable"
      )
    else
      checks << check(
        category: "agent_registration", name: "hooks_executable", status: "fail",
        message: "#{non_executable.size} hook script(s) not executable",
        details: non_executable.map { |p| tilde(p) },
        fixable: true, fix_hint: "chmod +x on the listed files"
      )
    end

    # hooks_no_orphans: the mirror of hooks_exist. A plastic-* launcher on disk
    # that HookRegistry does not know about is dead code the next reader would
    # trust as live (the same drift class as a missing launcher, just facing
    # the other way). plastic-statusline is a legitimate non-hook installer
    # artifact (see CLAUDE_NON_HOOK_LAUNCHERS) and is excluded here.
    present_launchers = Dir.glob(File.join(hooks_dir, "plastic-*")).map { |p| File.basename(p) }
    orphans = (present_launchers - expected_launchers - CLAUDE_NON_HOOK_LAUNCHERS).sort

    if orphans.empty?
      checks << check(
        category: "agent_registration", name: "hooks_no_orphans", status: "pass",
        message: "No orphaned hook launchers in #{tilde(hooks_dir)}"
      )
    else
      checks << check(
        category: "agent_registration", name: "hooks_no_orphans", status: "warn",
        message: "#{orphans.size} hook launcher(s) on disk are not registered in HookRegistry",
        details: orphans.map { |h| "#{tilde(hooks_dir)}/#{h}" },
        fixable: true,
        fix_hint: "Re-run the Plastic installer: npx @zalom/plastic@latest --claude (prunes stale launchers)"
      )
    end

    # hooks_registered — settings.json has Plastic hooks for required events
    settings_path = File.join(agent_dir, "settings.json")
    settings = read_json_safe(settings_path)

    if settings.nil?
      checks << check(
        category: "agent_registration", name: "hooks_registered", status: "fail",
        message: "Cannot read #{tilde(settings_path)} — file missing or invalid",
        fixable: true, fix_hint: "Re-run the Plastic installer: npx @zalom/plastic@latest --claude"
      )
    else
      hooks = settings["hooks"] || {}
      missing_events = CLAUDE_HOOK_EVENTS.reject do |event|
        groups = hooks[event]
        next false unless groups.is_a?(Array)

        groups.any? do |group|
          group.is_a?(Hash) && group["hooks"].is_a?(Array) &&
            group["hooks"].any? { |h| h["command"].to_s.include?("plastic-") }
        end
      end

      if missing_events.empty?
        checks << check(
          category: "agent_registration", name: "hooks_registered", status: "pass",
          message: "All #{CLAUDE_HOOK_EVENTS.size} hook events registered in settings.json"
        )
      else
        checks << check(
          category: "agent_registration", name: "hooks_registered", status: "fail",
          message: "#{missing_events.size} hook event(s) not registered in settings.json",
          details: missing_events,
          fixable: true, fix_hint: "Re-run the Plastic installer: npx @zalom/plastic@latest --claude"
        )
      end

      # hooks_match_registry (intent 108, D7): the live settings must carry
      # EXACTLY the registrations HookRegistry defines; any drift (a missing
      # gate, a stray plastic hook, a stale matcher) is how bash-gate shipped
      # dead once already.
      expected = HookRegistry.claude_settings_hooks(hook_dir: hooks_dir)
      diffs = []
      expected.each do |event, group|
        groups = group.is_a?(Array) ? group : [group]
        live = settings.dig("hooks", event) || []
        groups.each do |g|
          matches = live.select { |h| h.is_a?(Hash) && h["matcher"] == g["matcher"] }
          wanted = g["hooks"].map { |h| h["command"] }
          got = matches.flat_map { |m| Array(m["hooks"]).map { |h| h["command"] } }
          missing = wanted - got
          diffs << "#{event}[#{g['matcher']}] missing: #{missing.join(', ')}" unless missing.empty?
        end
      end
      live_plastic = (settings["hooks"] || {}).flat_map do |event, groups|
        Array(groups).flat_map do |g|
          next [] unless g.is_a?(Hash) && g["hooks"].is_a?(Array)
          g["hooks"].map { |h| h["command"].to_s }.select { |c| c.include?("plastic-") }
                    .map { |c| "#{event}: #{c}" }
        end
      end
      expected_cmds = expected.values.flat_map { |g| g.is_a?(Array) ? g : [g] }
                              .flat_map { |g| g["hooks"].map { |h| h["command"] } }
      strays = live_plastic.reject { |lp| expected_cmds.any? { |c| lp.end_with?(c) } }
      diffs.concat(strays.map { |s| "stray: #{s}" })

      checks << if diffs.empty?
        check(category: "agent_registration", name: "hooks_match_registry",
              status: "pass", message: "settings.json hooks match HookRegistry")
      else
        check(category: "agent_registration", name: "hooks_match_registry",
              status: "fail", message: "#{diffs.size} hook registration(s) diverge from HookRegistry",
              details: diffs, fixable: true,
              fix_hint: "Re-run the installer merge: npx @zalom/plastic update (or ruby ~/.plastic/scripts/install.rb)")
      end
    end

    # skills_exist — flat, hyphen-namespaced personal skills (plastic-<name>/)
    checks << flat_skills_check(agent_dir, "--claude")

    # stray_skills — installed plastic-* skill dir with no manifest entry (a leftover,
    # e.g. an old-name copy after a rename; intent 158a AC15)
    stray_check = stray_skills_check(agent_dir, "--claude", File.join(agent_dir, "plastic", "manifest.json"))
    checks << stray_check if stray_check

    # agents_exist — auto-mode role files (plastic-*.md) synced into <dir>/agents
    checks << flat_agents_check(agent_dir, "--claude")

    checks
  end

  # Plastic skills install as ~/.claude/skills/plastic-<name>/SKILL.md. Pass if at
  # least one such skill is present.
  def flat_skills_check(agent_dir, installer_flag)
    skills_root = File.join(agent_dir, "skills")
    found = Dir.glob(File.join(skills_root, "plastic-*", "SKILL.md"))

    if !found.empty?
      check(
        category: "agent_registration", name: "skills_exist", status: "pass",
        message: "#{found.size} plastic-* skill(s) installed in #{tilde(skills_root)}"
      )
    else
      check(
        category: "agent_registration", name: "skills_exist", status: "fail",
        message: "No plastic-* skills found in #{tilde(skills_root)}",
        fixable: true, fix_hint: "Re-run the Plastic installer: npx @zalom/plastic@latest #{installer_flag}"
      )
    end
  end

  # Backstop for a rename or removal (intent 158a, AC15): an installed plastic-*
  # skill directory under agent_dir/skills that has NO corresponding entry in the
  # current install manifest is a stray (e.g. a leftover old-name copy the
  # install/update prune should have removed, or one it never saw because the
  # manifest predates it). Complements flat_skills_check (which only confirms at
  # least one skill exists). Defers to the manifest check when the manifest itself
  # is missing or malformed, so the two checks never double-report the same gap.
  def stray_skills_check(agent_dir, installer_flag, manifest_path)
    skills_root = File.join(agent_dir, "skills")
    manifest = read_json_safe(manifest_path)
    files = manifest.is_a?(Hash) ? manifest["files"] : nil
    return nil unless files.is_a?(Hash)

    installed = Dir.glob(File.join(skills_root, "plastic-*", "SKILL.md"))
                    .map { |f| File.basename(File.dirname(f)) }
    tracked = files.keys
                   .select { |p| p.start_with?("#{skills_root}/") }
                   .map { |p| p.sub("#{skills_root}/", "").split("/").first }
                   .uniq

    strays = (installed - tracked).sort

    if strays.empty?
      check(
        category: "agent_registration", name: "stray_skills", status: "pass",
        message: "No stray plastic-* skill directories in #{tilde(skills_root)}"
      )
    else
      check(
        category: "agent_registration", name: "stray_skills", status: "warn",
        message: "#{strays.size} installed skill dir(s) not in the current manifest (stray, e.g. a leftover old-name copy)",
        details: strays,
        fixable: true, fix_hint: "Re-run the Plastic installer: npx @zalom/plastic@latest #{installer_flag}"
      )
    end
  end

  # Auto-mode role agents install as <dir>/agents/plastic-*.md. Pass if at least
  # one such role file is present (the installer syncs agents/ on every install).
  def flat_agents_check(agent_dir, installer_flag)
    agents_root = File.join(agent_dir, "agents")
    found = Dir.glob(File.join(agents_root, "plastic-*.md"))

    if !found.empty?
      check(
        category: "agent_registration", name: "agents_exist", status: "pass",
        message: "#{found.size} plastic-* agent(s) installed in #{tilde(agents_root)}"
      )
    else
      check(
        category: "agent_registration", name: "agents_exist", status: "fail",
        message: "No plastic-* agents found in #{tilde(agents_root)}",
        fixable: true, fix_hint: "Re-run the Plastic installer: npx @zalom/plastic@latest #{installer_flag}"
      )
    end
  end

  # Shared skills-presence plus stray-skills check, used by both the generic
  # (hermes) agent-registration path and codex's TOML-based one. Neither the flat
  # `.md` agents check nor anything agent-format-specific lives here.
  def check_flat_skills_and_stray(agent_key, agent_dir)
    checks = []

    # For codex/hermes: just check skills exist (no settings.json hooks)
    checks << flat_skills_check(agent_dir, "--#{agent_key}")

    # stray_skills — installed plastic-* skill dir with no manifest entry (a leftover,
    # e.g. an old-name copy after a rename; intent 158a AC15)
    stray_check = stray_skills_check(agent_dir, "--#{agent_key}", File.join(agent_dir, "plastic", "manifest.json"))
    checks << stray_check if stray_check

    checks
  end

  def check_generic_agent_registration(agent_key, agent_dir)
    checks = check_flat_skills_and_stray(agent_key, agent_dir)
    checks << flat_agents_check(agent_dir, "--#{agent_key}")   # hermes: unchanged (.md copy)
    checks
  end

  # Codex marker literals. Keep in sync with InstallerCore::CODEX_SECTION_BEGIN_PREFIX /
  # CODEX_SECTION_END (doctor does not require installer_core, so the literals are duplicated).
  CODEX_SECTION_BEGIN_PREFIX = "<!-- BEGIN PLASTIC INTEGRATION"
  CODEX_SECTION_END = "<!-- END PLASTIC INTEGRATION -->"

  def check_codex_registration(agent_key, agent_dir)
    config = agents[agent_key]
    checks = check_flat_skills_and_stray(agent_key, agent_dir)
    checks << codex_agents_toml_check(config)

    agents_md = File.join(config[:home_dir], "AGENTS.md")

    if !File.exist?(agents_md)
      checks << check(
        category: "agent_registration", name: "codex_agents_md", status: "fail",
        message: "Codex AGENTS.md not found at #{tilde(agents_md)}",
        fixable: true, fix_hint: "Re-run the Plastic installer with --codex"
      )
    else
      content = File.read(agents_md)
      b = content.index(CODEX_SECTION_BEGIN_PREFIX)
      e = content.index(CODEX_SECTION_END)
      well_formed = b && e && e > b && content[b...e].include?("-->")
      if well_formed
        checks << check(
          category: "agent_registration", name: "codex_agents_md", status: "pass",
          message: "Codex AGENTS.md carries the Plastic section"
        )
      else
        checks << check(
          category: "agent_registration", name: "codex_agents_md", status: "fail",
          message: "Codex AGENTS.md is missing or has a malformed Plastic section",
          fixable: true, fix_hint: "Re-run the Plastic installer with --codex"
        )
      end
    end

    hooks_check = codex_hooks_registered_check(config)
    checks << hooks_check
    checks << codex_hooks_implemented_check(config)
    checks << codex_hook_trust_advisory_check if hooks_check[:status] == "pass"
    codex_config_toml_advisory_check(config).tap { |c| checks << c if c }
    codex_version_floor_check(config).tap { |c| checks << c if c }

    checks
  end

  # Hooks being REGISTERED (hooks.json content matches HookRegistry) is not
  # the same as hooks being TRUSTED: Codex gates every non-managed hook
  # command behind a human /hooks review, keyed by the command's current
  # hash, so a release that changes a hook command re-arms the review
  # (intent 198, Decision D2). Whether Codex persists a queryable trust
  # record anywhere under ~/.codex is undocumented and unverified, so this
  # can never be a real pass or fail on trust state; it is an advisory that
  # always names the /hooks step, and it fires only once hooks are actually
  # registered (an unregistered hook is already reported by
  # codex_hooks_registered_check, so reminding about trust on top of that
  # would be noise, not signal).
  def codex_hook_trust_advisory_check
    check(
      category: "agent_registration", name: "codex_hooks_trust", status: "warn",
      message: "Open Codex, run /hooks, and trust the Plastic hook definitions. " \
               "Codex re-arms this review whenever a hook's command changes.",
      fixable: false
    )
  end

  # Codex-specific agent presence + structural sanity: ~/.codex/agents/plastic-*.toml
  # exist and each carries the mandatory fields. No TOML parser (doctor depends on none):
  # "structural" means the mandatory keys appear as lines and the multi-line
  # developer_instructions string is balanced (an opening triple-quote has a later one).
  def codex_agents_toml_check(config)
    agents_root = File.join(config[:home_dir], "agents")
    found = Dir.glob(File.join(agents_root, "plastic-*.toml"))

    if found.empty?
      return check(
        category: "agent_registration", name: "codex_agents_toml", status: "fail",
        message: "No plastic-* agent TOML files found in #{tilde(agents_root)}",
        fixable: true, fix_hint: "Re-run the Plastic installer with --codex"
      )
    end

    malformed = found.reject { |f| codex_agent_toml_well_formed?(File.read(f)) }
    if malformed.empty?
      check(
        category: "agent_registration", name: "codex_agents_toml", status: "pass",
        message: "#{found.size} plastic-* agent TOML(s) installed in #{tilde(agents_root)}"
      )
    else
      check(
        category: "agent_registration", name: "codex_agents_toml", status: "fail",
        message: "#{malformed.size} Codex agent TOML(s) missing mandatory fields",
        details: malformed.map { |f| tilde(f) },
        fixable: true, fix_hint: "Re-run the Plastic installer with --codex"
      )
    end
  end

  def codex_agent_toml_well_formed?(content)
    marker = 'developer_instructions = """'
    di = content.index(marker)
    has_name = content.match?(/^name\s*=\s*"/)
    has_desc = content.match?(/^description\s*=\s*"/)
    balanced = di && content.index('"""', di + marker.length)
    has_name && has_desc && !di.nil? && !balanced.nil?
  end

  # Plain string extraction of the single model-selection line a generated
  # Codex agent TOML carries (model_reasoning_effort for a tier alias, model
  # for a literal override id; codex_model_fields never emits both). No TOML
  # parser dependency, mirroring codex_agent_toml_well_formed? above.
  def codex_agent_toml_model_value(content)
    m = content.match(/^model_reasoning_effort\s*=\s*"([^"]*)"/) || content.match(/^model\s*=\s*"([^"]*)"/)
    m && m[1]
  end

  # codex_hooks_registered (intent 102, the owner-facing first-run validation
  # path, Decision 14): ~/.codex/hooks.json must carry EXACTLY the commands
  # HookRegistry.codex_hooks_json defines, mirroring the Claude
  # hooks_match_registry diff. Never writes.
  def codex_hooks_registered_check(config)
    hooks_json = File.join(config[:home_dir], "hooks.json")
    dispatcher = File.join(plastic_home, "scripts", "codex-hook")
    data = read_json_safe(hooks_json)

    if data.nil?
      return check(
        category: "agent_registration", name: "codex_hooks_registered", status: "fail",
        message: "Codex hooks.json missing or unreadable at #{tilde(hooks_json)}",
        fixable: true, fix_hint: "Re-run the Plastic installer with --codex"
      )
    end

    expected = HookRegistry.codex_hooks_json(dispatcher_path: dispatcher)
    live = data["hooks"] || {}
    missing = []
    expected.each do |event, groups|
      want = Array(groups).flat_map { |g| g["hooks"].map { |h| h["command"] } }
      got = Array(live[event]).flat_map { |g| Array(g["hooks"]).map { |h| h["command"] } }
      missing.concat(want - got)
    end

    if missing.empty?
      check(
        category: "agent_registration", name: "codex_hooks_registered", status: "pass",
        message: "Codex hooks registered in hooks.json"
      )
    else
      check(
        category: "agent_registration", name: "codex_hooks_registered", status: "fail",
        message: "Codex hooks.json missing #{missing.size} command(s)",
        details: missing,
        fixable: true, fix_hint: "Re-run the Plastic installer with --codex"
      )
    end
  end

  # codex_hooks_implemented (intent 200): codex_hooks_registered_check above proves
  # hooks.json content matches what HookRegistry would emit; both sides of THAT
  # comparison come from the registry, so a pass only proves the registry agrees
  # with itself. It never looks at the actual dispatcher, so it cannot see a
  # registered gate with no real branch there (links-gate shipped exactly this way,
  # dead, in v1.4.0/intent 192, invisible to doctor and the suite until 198 found it
  # by hand), or a dispatcher branch nobody registers (bash-gate's shape, intent
  # 203, in the opposite direction). This check closes both directions at once.

  # The Codex gate names HookRegistry actually registers: the six apply_patch-gated
  # names (CODEX_PRE_HOOKS + CODEX_POST_HOOKS), the two Bash-matcher shell gates
  # (CODEX_BASH_HOOKS), and the live-state hook names Codex inherits whole from
  # `events` (CODEX_LIVE_STATE_EVENTS). No parsing needed: these are HookRegistry's
  # own Ruby constants.
  def codex_registry_gate_names
    live_state = HookRegistry::CODEX_LIVE_STATE_EVENTS.flat_map do |event|
      HookRegistry.events[event].flat_map { |g| g["hooks"].map { |h| h["name"] } }
    end
    (HookRegistry::CODEX_PRE_HOOKS + HookRegistry::CODEX_POST_HOOKS +
     HookRegistry::CODEX_BASH_HOOKS + live_state).uniq
  end

  # Source-text extraction of scripts/codex-hook's supported gate names (D3): the
  # dispatcher is an executable script with real top-level side effects (it reads
  # $stdin and may exit), so it can never be required or executed to introspect it,
  # only read as plain text, mirroring codex_agent_toml_well_formed? above. Pulls
  # gate names from the STATE_HOOKS and SHELL_HOOKS %w[] literals, plus the `when
  # "<name>"` labels of the top-level `case gate` statement (stopping at its
  # trailing `else`). Line-shape dependent, not AST-safe, disclosed as such in
  # docs; the healthy-install pass test against the REAL dispatcher is what proves
  # this shape still holds.
  #
  # SELF-CHECKING: returns nil, never [], when nothing recognizable is found. A
  # reshaped dispatcher (combined `when "a", "b"` arms, a multi-line array, a
  # Hash-dispatch rewrite) would otherwise silently read as zero gate names, and a
  # zero-gate dispatcher would make the diff below either flag every registered
  # hook as "missing" or, worse, quietly under-report a real gap. A check that
  # finds nothing and calls that healthy IS the exact disease this whole check
  # exists to catch, one level up, so nil forces the caller (below) to fail loudly
  # instead of reporting health it never actually verified.
  def codex_dispatcher_gate_names(source)
    names = []
    %w[STATE_HOOKS SHELL_HOOKS].each do |const|
      m = source.match(/^#{const}\s*=\s*%w\[([^\]]*)\]/)
      names.concat(m[1].split(/\s+/)) if m
    end

    case_start = source.index(/^case gate\b/)
    if case_start
      case_body = source[case_start..-1]
      else_idx = case_body.index(/^else\b/)
      scanned = else_idx ? case_body[0...else_idx] : case_body
      names.concat(scanned.scan(/^when\s+"([^"]+)"/).flatten)
    end

    names.uniq!
    names.empty? ? nil : names
  end

  # The both-direction diff. Each mismatch becomes one detail line naming the
  # hook, the direction, the harness ("Codex"), and the concrete runtime effect,
  # never a generic "Codex hooks drift" message (D4).
  def codex_hooks_implemented_check(config)
    dispatcher_path = File.join(plastic_home, "scripts", "codex-hook")

    unless File.exist?(dispatcher_path)
      return check(
        category: "agent_registration", name: "codex_hooks_implemented", status: "fail",
        message: "scripts/codex-hook not found at #{tilde(dispatcher_path)}; cannot verify " \
                 "the Codex hook registry and dispatcher agree",
        fixable: true, fix_hint: "Re-run the Plastic installer with --codex"
      )
    end

    dispatcher_names = codex_dispatcher_gate_names(File.read(dispatcher_path))

    if dispatcher_names.nil?
      return check(
        category: "agent_registration", name: "codex_hooks_implemented", status: "fail",
        message: "Could not read any gate names out of #{tilde(dispatcher_path)}: the " \
                 "STATE_HOOKS/SHELL_HOOKS constants and the `case gate` statement no longer " \
                 "match the shape this check expects, so the registry could not be checked " \
                 "against the real dispatcher. This is exactly the silent-pass failure this " \
                 "check exists to prevent; update codex_dispatcher_gate_names in doctor.rb " \
                 "to the file's new shape.",
        fixable: false
      )
    end

    registry_names = codex_registry_gate_names
    missing_dispatcher_branch = registry_names - dispatcher_names
    dead_branch = dispatcher_names - registry_names

    if missing_dispatcher_branch.empty? && dead_branch.empty?
      return check(
        category: "agent_registration", name: "codex_hooks_implemented", status: "pass",
        message: "Every Codex-registered gate has a scripts/codex-hook branch, and every " \
                 "dispatcher branch is registered"
      )
    end

    details = missing_dispatcher_branch.map do |name|
      "#{name} is registered in ~/.codex/hooks.json but scripts/codex-hook has no branch " \
        "for it, so it always falls through to the fail-open else and always allows the write"
    end
    details += dead_branch.map do |name|
      "#{name} has a branch in scripts/codex-hook but is not registered in HookRegistry for " \
        "Codex, so it is dead code Codex never reaches"
    end

    check(
      category: "agent_registration", name: "codex_hooks_implemented", status: "fail",
      message: "Codex's hook registry and scripts/codex-hook disagree on #{details.size} gate(s)",
      details: details,
      fixable: false
    )
  end

  # config.toml advisory (intent 102, Decision 2, R2): READ ONLY. Warns on the two
  # documented footguns (hooks disabled, sandbox read-only); never writes, and
  # returns nil (no check emitted) when config.toml is absent or carries neither.
  def codex_config_toml_advisory_check(config)
    config_toml = File.join(config[:home_dir], "config.toml")
    return nil unless File.exist?(config_toml)

    toml = File.read(config_toml) rescue ""
    warns = []
    # guide Part 3: `codex_hooks` is a deprecated alias for `[features] hooks`; catch both.
    warns << "hooks are disabled ([features] hooks = false); Plastic gates will not fire" if toml.match?(/^\s*(?:codex_)?hooks\s*=\s*false/)
    warns << "sandbox_mode = \"read-only\"; apply_patch writes (and gates) cannot run" if toml.match?(/^\s*sandbox_mode\s*=\s*["']read-only["']/)
    return nil if warns.empty?

    check(
      category: "agent_registration", name: "codex_config_advisory", status: "warn",
      message: warns.join("; "),
      fixable: false,
      fix_hint: "Set [features] hooks = true and sandbox_mode = \"workspace-write\" in ~/.codex/config.toml"
    )
  end

  # Codex version-floor advisory (intent 184): READ ONLY. The apply_patch PreToolUse
  # veto (scripts/lib/hook_registry.rb, scripts/codex-hook) only fires from Codex
  # v0.123.0 (PR #18391); below it the veto silently no-ops. version.json is Codex's
  # update-checker cache and holds no installed version, so the only install-method-
  # agnostic source is `codex --version`, shelled out through the injected runner.
  # Four honest branches (intent 208, no pass-by-construction): absent home -> nil;
  # present but undetectable -> distinct warn; below floor -> warn; at/above -> pass.
  def codex_version_floor_check(config)
    return nil unless File.exist?(config[:home_dir])

    stdout, ok = @runner.call(["--version"])
    version = ok ? codex_version_from_output(stdout) : nil
    parsed = version && safe_version(version)

    if parsed.nil?
      return check(
        category: "agent_registration", name: "codex_version_floor", status: "warn",
        message: "Could not determine the installed Codex version (`codex --version` did not " \
                 "return a parseable version); Plastic cannot confirm the apply_patch hooks " \
                 "floor v#{CODEX_HOOKS_FLOOR} is met, so its gate may silently no-op",
        fixable: false,
        fix_hint: "Ensure `codex` is on PATH and `codex --version` >= #{CODEX_HOOKS_FLOOR}"
      )
    end

    if parsed < safe_version(CODEX_HOOKS_FLOOR)
      return check(
        category: "agent_registration", name: "codex_version_floor", status: "warn",
        message: "Installed Codex #{version} predates v#{CODEX_HOOKS_FLOOR}; the apply_patch " \
                 "PreToolUse veto only exists from v#{CODEX_HOOKS_FLOOR} (PR #18391), so Plastic's " \
                 "gate silently no-ops on this install",
        fixable: false,
        fix_hint: "Upgrade Codex to v#{CODEX_HOOKS_FLOOR} or newer with your install method " \
                  "(npm i -g @openai/codex, mise, homebrew, or cargo)"
      )
    end

    check(
      category: "agent_registration", name: "codex_version_floor", status: "pass",
      message: "Codex #{version} meets the apply_patch hooks floor v#{CODEX_HOOKS_FLOOR}"
    )
  end

  def codex_version_from_output(stdout)
    m = stdout.to_s.match(/(\d+\.\d+\.\d+(?:[.\-+][0-9A-Za-z.\-+]*)?)/)
    m && m[1]
  end

  def safe_version(str)
    Gem::Version.new(str.to_s)
  rescue ArgumentError
    nil
  end

  # --- Check category 4: Core files ---

  def check_core_files(agent_key, include_drift: true)
    checks = []

    # plastic_md
    plastic_md = File.join(plastic_home, "PLASTIC.md")
    if File.exist?(plastic_md)
      checks << check(
        category: "core_files", name: "plastic_md", status: "pass",
        message: "PLASTIC.md exists"
      )
    else
      checks << check(
        category: "core_files", name: "plastic_md", status: "fail",
        message: "PLASTIC.md not found at #{tilde(plastic_md)}",
        fixable: true, fix_hint: "Re-run the Plastic installer to restore core files"
      )
    end

    # version_file
    version_path = File.join(plastic_home, "VERSION")
    if File.exist?(version_path)
      checks << check(
        category: "core_files", name: "version_file", status: "pass",
        message: "VERSION file exists"
      )
    else
      checks << check(
        category: "core_files", name: "version_file", status: "fail",
        message: "VERSION file not found at #{tilde(version_path)}",
        fixable: true, fix_hint: "Re-run the Plastic installer to restore core files"
      )
    end

    # scripts_present
    scripts_dir = File.join(plastic_home, "scripts")
    missing_scripts = REQUIRED_SCRIPTS.reject { |s| File.exist?(File.join(scripts_dir, s)) }

    if missing_scripts.empty?
      checks << check(
        category: "core_files", name: "scripts_present", status: "pass",
        message: "All #{REQUIRED_SCRIPTS.size} required scripts present"
      )
    else
      checks << check(
        category: "core_files", name: "scripts_present", status: "fail",
        message: "#{missing_scripts.size} required script(s) missing from #{tilde(scripts_dir)}",
        details: missing_scripts,
        fixable: true, fix_hint: "Re-run the Plastic installer to restore scripts"
      )
    end

    # scripts_executable
    if File.directory?(scripts_dir)
      script_files = Dir.children(scripts_dir)
        .map { |f| File.join(scripts_dir, f) }
        .select { |f| File.file?(f) }

      non_executable = script_files.reject { |f| File.executable?(f) }

      if non_executable.empty?
        checks << check(
          category: "core_files", name: "scripts_executable", status: "pass",
          message: "All scripts in #{tilde(scripts_dir)} are executable"
        )
      else
        checks << check(
          category: "core_files", name: "scripts_executable", status: "fail",
          message: "#{non_executable.size} script(s) not executable",
          details: non_executable.map { |f| tilde(f) },
          fixable: true, fix_hint: "chmod +x on the listed files"
        )
      end
    end

    # version_match — compare global VERSION with agent-side VERSION
    global_version = read_version
    agent_config = agents[agent_key]

    if global_version && agent_config
      agent_version_path = case agent_key
                           when "claude" then File.join(agent_config[:dir], "plastic", "VERSION")
                           else File.join(agent_config[:dir], "plastic", "VERSION")
                           end

      if File.exist?(agent_version_path)
        agent_version = File.read(agent_version_path).strip

        if global_version == agent_version
          checks << check(
            category: "core_files", name: "version_match", status: "pass",
            message: "Global VERSION (#{global_version}) matches agent-side VERSION"
          )
        else
          checks << check(
            category: "core_files", name: "version_match", status: "warn",
            message: "Version mismatch: global=#{global_version}, agent=#{agent_version}",
            details: [
              "#{tilde(File.join(plastic_home, "VERSION"))}: #{global_version}",
              "#{tilde(agent_version_path)}: #{agent_version}",
            ],
            fixable: true,
            fix_hint: "Re-sync the stale harness: npx @zalom/plastic@latest install --reinstall <flag>, or plastic-rollback to a prior version"
          )
        end
      else
        checks << check(
          category: "core_files", name: "version_match", status: "warn",
          message: "Agent-side VERSION file not found at #{tilde(agent_version_path)}",
          fixable: true,
          fix_hint: "Re-sync the stale harness: npx @zalom/plastic@latest install --reinstall <flag>, or plastic-rollback to a prior version"
        )
      end
    end

    checks += check_agent_model_drift(agent_key) if include_drift

    checks
  end

  # agent_model_drift - advisory (never fail) config-vs-frontmatter comparison
  # for every installed <agent_dir>/agents/plastic-*.md file (intent 170, D1;
  # reclassified intent 191). Resolution mirrors read-config's own precedence
  # (project override -> global override -> shipped AgentModels::TIER_DEFAULTS),
  # reusing AgentModels' `override_map` directly so this stays hermetically
  # DI-testable (no shell-out to `read-config`, no ENV/global seam). There is
  # no live project scope at doctor-run time for a globally-installed agent
  # file, so the project layer is empty here; the resolver still supports one,
  # matching the same `override_map(project_config:, global_config:)` shape
  # the installer already calls.
  #
  # This check deliberately never diffs installed frontmatter against the
  # shipped agents/*.md source tree directly (considered and rejected, intent
  # 191): at real doctor run time doctor.rb lives at ~/.plastic/scripts/doctor.rb,
  # and the installer copies only scripts/ into ~/.plastic, never the agents/
  # tree, so a "compare against shipped frontmatter" check would find nothing
  # in the field and pass silently on every real installation while only ever
  # exercising itself inside the repo, the same dead-in-production shape
  # already documented above check_skill_lint. The only registry of sanctioned
  # defaults reachable at doctor run time is scripts/lib/agent_models.rb (it
  # IS copied into ~/.plastic/scripts/lib), so this check classifies each
  # installed basename using ONLY the two registries that module already
  # ships, TIER_DEFAULTS and CONSULTATION_AGENTS. No new model values are
  # added anywhere.
  #
  # Classification per installed agent basename, checked in this order:
  #   1. an `agents.models.<basename>` override IS configured -> sanctioned,
  #      pass/informational, LISTED regardless of whether frontmatter matches
  #      (that mismatch is the override working, e.g. plastic-brainstorming: fable).
  #   2. no override AND basename is a TIER_DEFAULTS key -> compare frontmatter
  #      to that default; match is pass (clean), mismatch is real drift (warn).
  #   3. no override AND basename is a CONSULTATION_AGENTS member -> not a
  #      lifecycle stage role (intent 185); its model is user configuration by
  #      contract (PLASTIC.md: "their models are user configuration"), so this
  #      check does not compare and does not warn, it only lists the agent
  #      informationally as a consultation role.
  #   4. no override AND basename is in NEITHER registry -> unclassified. This
  #      check has no ground truth for this agent, so it does not claim
  #      "drift vs default nil" (that claim would be false); it reports,
  #      advisory warn, that the agent is present in the installed agents dir
  #      but absent from both registries in scripts/lib/agent_models.rb, and
  #      names that file as the place to add it. Setting an
  #      agents.models.<basename> override also silences this line, by
  #      routing the agent through bucket 1.
  #   - zero installed agent files -> pass (nothing to check)
  # This check never returns "fail" (bucket 4 is an advisory warn, not a fail).
  def check_agent_model_drift(agent_key)
    agent_config = agents[agent_key]
    return [] unless agent_config

    return check_agent_model_drift_codex(agent_config) if agent_key == "codex"

    agents_dir = File.join(agent_config[:dir], "agents")
    installed = Dir.glob(File.join(agents_dir, "plastic-*.md")).sort

    if installed.empty?
      return [check(
        category: "core_files", name: "agent_model_drift", status: "pass",
        message: "No installed plastic-* agent files to check for model drift"
      )]
    end

    global_config = load_yaml_safe(File.join(plastic_home, "config.yml")) || {}
    overrides = AgentModels.override_map(project_config: {}, global_config: global_config)

    drifted = []
    sanctioned = []
    consultation = []
    unclassified = []

    installed.each do |path|
      basename = File.basename(path, ".md")
      installed_model = (parse_frontmatter(path) || {})["model"]
      override = overrides[basename]

      if override
        sanctioned << "#{basename}: frontmatter=#{installed_model.inspect}, sanctioned override=#{override.inspect}"
      elsif AgentModels::TIER_DEFAULTS.key?(basename)
        resolved_default = AgentModels::TIER_DEFAULTS[basename]
        if installed_model != resolved_default
          drifted << "#{basename}: frontmatter=#{installed_model.inspect}, resolved default=#{resolved_default.inspect}"
        end
      elsif AgentModels::CONSULTATION_AGENTS.include?(basename)
        consultation << "#{basename}: frontmatter=#{installed_model.inspect} (consultation role, not a lifecycle default, model is user configuration)"
      else
        unclassified << "#{basename}: frontmatter=#{installed_model.inspect}, no resolved default (basename is in neither AgentModels::TIER_DEFAULTS nor AgentModels::CONSULTATION_AGENTS in scripts/lib/agent_models.rb; add it there, or set agents.models.#{basename} to sanction a model explicitly)"
      end
    end

    if drifted.empty? && unclassified.empty?
      message = if sanctioned.empty?
                  "No agent-model drift (#{installed.size} installed agent(s) match the resolved default)"
                else
                  "No unsanctioned agent-model drift; #{sanctioned.size} sanctioned override(s) in effect"
                end
      [check(
        category: "core_files", name: "agent_model_drift", status: "pass",
        message: message,
        details: sanctioned + consultation
      )]
    else
      parts = []
      parts << "#{drifted.size} installed agent(s) have unsanctioned model drift vs the config-resolved default" if drifted.any?
      parts << "#{unclassified.size} installed agent(s) have no resolved default in scripts/lib/agent_models.rb" if unclassified.any?
      [check(
        category: "core_files", name: "agent_model_drift", status: "warn",
        message: parts.join("; "),
        details: drifted + unclassified + sanctioned + consultation,
        fixable: false
      )]
    end
  end

  # Codex leg of agent_model_drift (intent 198, Decision D4): the shared .md
  # path above is structurally blind on Codex (codex agents are TOML under
  # ~/.codex/agents/, never ~/.agents/agents/*.md), so it always passed on an
  # empty glob without opening a single Codex file. This mirrors the same
  # four buckets (sanctioned override, matches default, drifted,
  # unclassified) against ~/.codex/agents/plastic-*.toml instead, reading
  # model / model_reasoning_effort with the same plain string matching
  # codex_agent_toml_well_formed? already uses (no TOML parser dependency).
  # The expected value resolves through AgentModels::TIER_DEFAULTS mapped
  # through AgentModels.effort_for, honoring the Codex-scoped
  # agents.models.codex.<name> override precedence install_codex's own
  # agent_model_overrides(harness: "codex") already applies.
  # AgentModels::CONSULTATION_AGENTS need no special-case bucket here:
  # generate_codex_agents already skips writing them for Codex entirely, so
  # the glob below never finds them and there is nothing to classify.
  def check_agent_model_drift_codex(agent_config)
    agents_dir = File.join(agent_config[:home_dir], "agents")
    installed = Dir.glob(File.join(agents_dir, "plastic-*.toml")).sort

    if installed.empty?
      return [check(
        category: "core_files", name: "agent_model_drift", status: "pass",
        message: "No installed plastic-* agent TOML files to check for model drift"
      )]
    end

    global_config = load_yaml_safe(File.join(plastic_home, "config.yml")) || {}
    overrides = AgentModels.override_map(project_config: {}, global_config: global_config, harness: "codex")

    drifted = []
    sanctioned = []
    unclassified = []

    installed.each do |path|
      basename = File.basename(path, ".toml")
      installed_value = codex_agent_toml_model_value(File.read(path))
      override = overrides[basename]

      if override
        sanctioned << "#{basename}: toml=#{installed_value.inspect}, sanctioned override=#{override.inspect}"
      elsif AgentModels::TIER_DEFAULTS.key?(basename)
        expected_effort = AgentModels.effort_for(AgentModels::TIER_DEFAULTS[basename])
        if installed_value != expected_effort
          drifted << "#{basename}: toml=#{installed_value.inspect}, resolved default effort=#{expected_effort.inspect}"
        end
      else
        unclassified << "#{basename}: toml=#{installed_value.inspect}, no resolved default (basename is in " \
                         "neither AgentModels::TIER_DEFAULTS nor AgentModels::CONSULTATION_AGENTS in " \
                         "scripts/lib/agent_models.rb; add it there, or set agents.models.codex.#{basename} " \
                         "to sanction a model explicitly)"
      end
    end

    if drifted.empty? && unclassified.empty?
      message = if sanctioned.empty?
                  "No agent-model drift (#{installed.size} installed Codex agent TOML(s) match the resolved default)"
                else
                  "No unsanctioned Codex agent-model drift; #{sanctioned.size} sanctioned override(s) in effect"
                end
      [check(
        category: "core_files", name: "agent_model_drift", status: "pass",
        message: message,
        details: sanctioned
      )]
    else
      parts = []
      parts << "#{drifted.size} installed Codex agent TOML(s) have unsanctioned model drift vs the config-resolved default" if drifted.any?
      parts << "#{unclassified.size} installed Codex agent TOML(s) have no resolved default in scripts/lib/agent_models.rb" if unclassified.any?
      [check(
        category: "core_files", name: "agent_model_drift", status: "warn",
        message: parts.join("; "),
        details: drifted + unclassified + sanctioned,
        fixable: false
      )]
    end
  end

  # --- Check category: manifest sync (binary core integrity) ---

  # Verify, for BOTH the global manifest and the agent-side manifest, that every
  # file listed exists and its current SHA256 matches the recorded hash.
  #   - GLOBAL manifest:    <plastic_home>/manifest.json
  #   - AGENT-side manifest (every agent, intent 210 D2): <dir>/plastic/manifest.json
  # Manifest format: { "version", "created", "files": { abs_path => sha256 } }.
  # A missing manifest is a fail; any missing/mismatched listed file is a fail;
  # otherwise a single pass per manifest.
  def check_manifest_sync(agent_key)
    checks = []

    global_manifest = File.join(plastic_home, "manifest.json")
    checks << verify_manifest(global_manifest, "global")

    agent_dir = agents[agent_key][:dir]
    agent_manifest = File.join(agent_dir, "plastic", "manifest.json")
    checks << verify_manifest(agent_manifest, "agent")

    checks
  end

  # Check one manifest file. Returns a single check (pass or fail).
  def verify_manifest(manifest_path, label)
    unless File.exist?(manifest_path)
      return check(
        category: "manifest_sync", name: "#{label}_manifest", status: "fail",
        message: "#{label} core manifest missing — re-run the Plastic installer",
        details: [tilde(manifest_path)],
        fixable: true, fix_hint: "Re-run the Plastic installer"
      )
    end

    data = read_json_safe(manifest_path)
    files = data.is_a?(Hash) ? data["files"] : nil
    unless files.is_a?(Hash)
      return check(
        category: "manifest_sync", name: "#{label}_manifest", status: "fail",
        message: "#{label} core manifest unreadable or malformed — re-run the Plastic installer",
        details: [tilde(manifest_path)],
        fixable: true, fix_hint: "Re-run the Plastic installer"
      )
    end

    missing = []
    mismatched = []
    files.each do |path, recorded|
      unless File.exist?(path)
        missing << tilde(path)
        next
      end
      actual = Digest::SHA256.file(path).hexdigest
      mismatched << tilde(path) if actual != recorded
    end

    if missing.empty? && mismatched.empty?
      check(
        category: "manifest_sync", name: "#{label}_manifest", status: "pass",
        message: "#{label} manifest: all #{files.size} tracked file(s) present and matching"
      )
    else
      details = []
      details += missing.map { |p| "missing: #{p}" }
      details += mismatched.map { |p| "modified: #{p}" }
      check(
        category: "manifest_sync", name: "#{label}_manifest", status: "fail",
        message: "#{label} manifest out of sync: #{missing.size} missing, #{mismatched.size} modified",
        details: details,
        fixable: true, fix_hint: "Re-run the Plastic installer to restore tracked files"
      )
    end
  end

  # install_integrity (intent 210, D4): FULL tier only, warn-only, never writes. For each
  # installed agent, re-hash its manifest-listed files against disk and WARN on drift
  # (a hand-edit is legitimate; this is advisory, unlike the core-tier binary manifest_sync
  # gate). PASS when clean. `agents` here is doctor's own Hash keyed by agent key.
  def check_install_integrity
    checks = []
    agents.each do |key, config|
      manifest_path = File.join(config[:dir], "plastic", "manifest.json")
      next unless File.exist?(manifest_path)
      data = read_json_safe(manifest_path)
      files = data.is_a?(Hash) ? (data["files"] || {}) : {}
      next if files.empty?
      drifted = files.reject { |f, h| File.exist?(f) && Digest::SHA256.file(f).hexdigest == h }
      checks << if drifted.empty?
        check(category: "install_integrity", name: "#{key}_integrity", status: "pass",
              message: "#{config[:name]}: all #{files.size} tracked file(s) match the manifest")
      else
        check(category: "install_integrity", name: "#{key}_integrity", status: "warn",
              message: "#{config[:name]}: #{drifted.size} tracked file(s) differ from the manifest (drift may be deliberate)",
              details: drifted.keys.map { |f| tilde(f) }, fixable: true,
              fix_hint: "Re-sync if unintended: npx @zalom/plastic@latest install --reinstall --#{key}")
      end
    end
    checks
  end

  # --- Check category 5: Project stores ---

  def check_project_stores
    checks = []

    projects_yml_path = File.join(plastic_home, "projects.yml")
    projects_data = load_yaml_safe(projects_yml_path)

    if projects_data.nil?
      checks << check(
        category: "project_stores", name: "projects_yml", status: "warn",
        message: "projects.yml not found or invalid at #{tilde(projects_yml_path)}",
        fixable: true, fix_hint: "Re-run the Plastic installer to restore projects.yml"
      )
      return checks
    end

    projects = projects_data["projects"]
    unless projects.is_a?(Hash) && !projects.empty?
      # No projects registered — nothing to check
      checks << check(
        category: "project_stores", name: "projects_yml", status: "pass",
        message: "projects.yml is valid (#{projects.is_a?(Hash) ? projects.size : 0} projects registered)"
      )
      return checks
    end

    projects.each do |slug, project_info|
      checks += check_project_store(slug, project_info)
    end

    checks
  end

  # --- Check category: registered project paths (core-only, D1) ---
  #
  # D1 requires every registered project's store to have its repository path resolve to a
  # real, existing directory. check_project_store (above) only validates the plastic-home-side
  # mirror (~/.plastic/projects/<slug>/{store,INDEX.md,project.yml}); this method validates the
  # registered repo path itself (projects.yml's "path" key), decoupled from 175's deeper
  # repo-root-versus-registered-path question (219 D9).
  def check_registered_project_paths
    checks = []

    projects_yml_path = File.join(plastic_home, "projects.yml")
    projects_data = load_yaml_safe(projects_yml_path)

    if projects_data.nil?
      checks << check(
        category: "project_stores", name: "registered_project_paths", status: "fail",
        message: "projects.yml not found or invalid at #{tilde(projects_yml_path)}",
        fixable: true, fix_hint: "Re-run the Plastic installer to restore projects.yml"
      )
      return checks
    end

    projects = projects_data["projects"]
    unless projects.is_a?(Hash) && !projects.empty?
      checks << check(
        category: "project_stores", name: "registered_project_paths", status: "pass",
        message: "No projects registered"
      )
      return checks
    end

    projects.each do |slug, project_info|
      path = project_info.is_a?(Hash) ? project_info["path"] : nil

      if path && File.directory?(path)
        checks << check(
          category: "project_stores", name: "project_path_resolves", status: "pass",
          message: "Registered path for '#{slug}' resolves to a real directory"
        )
      else
        checks << check(
          category: "project_stores", name: "project_path_resolves", status: "fail",
          message: "Registered path for '#{slug}' does not resolve to a real directory",
          details: [path ? tilde(path) : "(no path set in projects.yml)"],
          fixable: false
        )
      end
    end

    checks
  end

  # Per-project validation extracted from check_project_stores so a single
  # project can be checked in isolation (used by `--store <slug>`).
  def check_project_store(slug, project_info)
    checks = []
    project_dir = File.join(plastic_home, "projects", slug)

    # project_dir_exists
    if File.directory?(project_dir)
      checks << check(
        category: "project_stores", name: "project_dir_exists", status: "pass",
        message: "Project directory exists for '#{slug}'"
      )
    else
      checks << check(
        category: "project_stores", name: "project_dir_exists", status: "warn",
        message: "Project directory missing for '#{slug}'",
        details: [tilde(project_dir)],
        fixable: true, fix_hint: "Create the project store directory: mkdir -p #{tilde(project_dir)}"
      )
    end

    # project_store_dir
    store_dir = File.join(project_dir, "store")
    if File.directory?(store_dir)
      checks << check(
        category: "project_stores", name: "project_store_dir", status: "pass",
        message: "Store directory exists for '#{slug}'"
      )
    else
      checks << check(
        category: "project_stores", name: "project_store_dir", status: "warn",
        message: "Store directory missing for '#{slug}'",
        details: [tilde(store_dir)],
        fixable: true, fix_hint: "Run: provision-project-store #{slug}"
      )
    end

    # project_index
    project_index = File.join(project_dir, "INDEX.md")
    if File.exist?(project_index)
      checks << check(
        category: "project_stores", name: "project_index", status: "pass",
        message: "INDEX.md exists for project '#{slug}'"
      )
    else
      checks << check(
        category: "project_stores", name: "project_index", status: "warn",
        message: "INDEX.md missing for project '#{slug}'",
        details: [tilde(project_index)],
        fixable: true, fix_hint: "Create INDEX.md in the project store directory"
      )
    end

    # project_yml_exists
    project_yml_path = File.join(plastic_home, "projects", slug, "project.yml")
    project_yml_data = nil

    if File.exist?(project_yml_path)
      checks << check(
        category: "project_stores", name: "project_yml_exists", status: "pass",
        message: "project.yml exists for project '#{slug}'"
      )
      project_yml_data = load_yaml_safe(project_yml_path)
    else
      checks << check(
        category: "project_stores", name: "project_yml_exists", status: "warn",
        message: "project.yml missing for project '#{slug}'",
        fixable: true, fix_hint: "Create project.yml from template — see plastic-project-creating"
      )
    end

    # governing_docs_exist
    if project_yml_data.is_a?(Hash) && project_yml_data["governing_docs"].is_a?(Array) && !project_yml_data["governing_docs"].empty?
      project_path = project_info.is_a?(Hash) ? project_info["path"] : nil

      if project_path
        missing_docs = project_yml_data["governing_docs"].reject do |doc_path|
          File.exist?(File.join(project_path, doc_path))
        end

        if missing_docs.empty?
          checks << check(
            category: "project_stores", name: "governing_docs_exist", status: "pass",
            message: "All governing docs exist for project '#{slug}'"
          )
        else
          checks << check(
            category: "project_stores", name: "governing_docs_exist", status: "warn",
            message: "#{missing_docs.size} governing doc(s) missing for project '#{slug}'",
            details: missing_docs,
            fixable: false
          )
        end
      end
    end

    # cross_references — if project has `parent` field, check global store intent tags
    parent_id = project_info.is_a?(Hash) ? project_info["parent"] : nil
    return checks unless parent_id

    # Find the intent directory for the parent ID
    store_dir = File.join(plastic_home, "store")
    parent_dir = nil
    if File.directory?(store_dir)
      parent_dir = Dir.children(store_dir).find { |d| d.start_with?("#{parent_id}--") }
    end

    if parent_dir.nil?
      checks << check(
        category: "project_stores", name: "cross_references", status: "warn",
        message: "Parent intent '#{parent_id}' for project '#{slug}' not found in global store",
        fixable: false
      )
      return checks
    end

    intent_md = File.join(store_dir, parent_dir, "#{parent_dir}.md")
    fm = parse_frontmatter(intent_md)

    if fm.nil?
      checks << check(
        category: "project_stores", name: "cross_references", status: "warn",
        message: "Cannot read frontmatter of parent intent '#{parent_id}' for project '#{slug}'",
        fixable: false
      )
      return checks
    end

    tags = fm["tags"]
    expected_tag = "project-#{slug}"

    if tags.is_a?(Array) && tags.include?(expected_tag)
      checks << check(
        category: "project_stores", name: "cross_references", status: "pass",
        message: "Parent intent '#{parent_id}' has '#{expected_tag}' tag for project '#{slug}'"
      )
    else
      checks << check(
        category: "project_stores", name: "cross_references", status: "warn",
        message: "Parent intent '#{parent_id}' missing '#{expected_tag}' tag",
        details: ["Intent: store/#{parent_dir}", "Expected tag: #{expected_tag}", "Current tags: #{(tags || []).inspect}"],
        fixable: false
      )
    end

    checks
  end

  # --- Check category 6: Deprecations ---

  def check_deprecations
    checks = []

    deprecations_path = File.join(plastic_home, "deprecations.yml")
    data = load_yaml_safe(deprecations_path)

    if data.nil?
      checks << check(
        category: "deprecations", name: "deprecations_file", status: "pass",
        message: "No deprecations.yml found (nothing to report)"
      )
      return checks
    end

    entries = data["deprecations"]
    unless entries.is_a?(Array) && !entries.empty?
      checks << check(
        category: "deprecations", name: "active_deprecations", status: "pass",
        message: "No deprecation entries found"
      )
      return checks
    end

    current_version = read_version
    unless current_version
      checks << check(
        category: "deprecations", name: "active_deprecations", status: "warn",
        message: "Cannot compare deprecation versions — VERSION file missing",
        fixable: false
      )
      return checks
    end

    # Find deprecations where removal version is greater than current version
    # Use simple string comparison on semver (works for well-formed versions)
    active = entries.select do |entry|
      removal = entry["removal"].to_s
      next false if removal.empty?

      compare_versions(current_version, removal) < 0
    end

    if active.empty?
      checks << check(
        category: "deprecations", name: "active_deprecations", status: "pass",
        message: "No active deprecations for current version (#{current_version})"
      )
    else
      details = active.map do |entry|
        lines = ["[#{entry["severity"]}] #{entry["summary"]} (removal: #{entry["removal"]})"]
        if entry["migration_steps"].is_a?(Array)
          entry["migration_steps"].each { |step| lines << "  - #{step}" }
        end
        lines.join("\n")
      end

      checks << check(
        category: "deprecations", name: "active_deprecations", status: "warn",
        message: "#{active.size} active deprecation(s) for version #{current_version}",
        details: details,
        fixable: false
      )
    end

    checks
  end

  # Compare two semver strings. Returns -1, 0, or 1.
  # Handles pre-release tags: 1.0.0-alpha.5 < 1.0.0 < 2.0.0
  def compare_versions(a, b)
    parse = ->(v) {
      base, pre = v.split("-", 2)
      segments = base.split(".").map(&:to_i)
      [segments, pre]
    }

    a_segments, a_pre = parse.call(a)
    b_segments, b_pre = parse.call(b)

    # Pad to equal length
    max_len = [a_segments.size, b_segments.size].max
    a_segments += [0] * (max_len - a_segments.size)
    b_segments += [0] * (max_len - b_segments.size)

    cmp = (a_segments <=> b_segments)
    return cmp unless cmp == 0

    # Same base version: no pre-release > pre-release (1.0.0 > 1.0.0-alpha)
    return 0 if a_pre.nil? && b_pre.nil?
    return 1 if a_pre.nil? && b_pre
    return -1 if a_pre && b_pre.nil?

    # Both have pre-release: compare lexically
    a_pre <=> b_pre
  end

  # --- Check category: config asks (release-introduced config questions) ---
  #
  # Reads config_asks.yml via ConfigAsks (intent 194): a shipped, declarative
  # manifest so a release can announce a new config question and collect the
  # answer without this file, update.rb, or any skill needing to change again.
  # Rolled up into one check (mirrors check_deprecations shape). Full-tier
  # (run_checks) ONLY, deliberately excluded from run_core_checks: the post-
  # update path (update.rb#run_post_update_doctor) defaults to the fast/core
  # tier, which rolls up with binary: true (any warn becomes overall "fail").
  # A config-asks warn in that tier would flip every post-update doctor to
  # "fail" on an otherwise healthy install until the question is answered,
  # re-noising the post-update surface intent 126 deliberately quieted. The
  # recoverable-later path for a pending question is a full `/plastic-doctor`
  # run, the declared maintenance front door; the moment-it-happens path is
  # update.rb#announce_pending_config_asks, which already runs on every hop.
  #
  # A manifest that exists but cannot be read or parsed is reported as its own
  # WARN (config_asks_manifest), never as a silent pass: an unreadable
  # manifest is not the same as "nothing declared", and reporting it as
  # healthy would be the exact silent-failure this whole batch exists to
  # close. agent_key filters entries by their optional agents scoping (an
  # entry with no agents field applies to every agent).
  def check_config_asks(agent_key = "claude")
    manifest_problem = ConfigAsks.manifest_error(plastic_home)
    if manifest_problem
      return [check(
        category: "config_asks", name: "config_asks_manifest", status: "warn",
        message: "config_asks.yml problem: #{manifest_problem}",
        fixable: false
      )]
    end

    pending = ConfigAsks.pending(plastic_home, agent_key)

    if pending.empty?
      return [check(
        category: "config_asks", name: "pending_asks", status: "pass",
        message: "No pending config questions"
      )]
    end

    details = pending.map do |entry|
      lines = ["#{entry["question"]} (id: #{entry["id"]})"]
      Array(entry["options"]).each do |opt|
        lines << "  - #{opt["label"]}"
        lines << "    #{ConfigAsks.write_config_command(plastic_home, entry["key"], opt["value"])}"
      end
      lines << "  - Not now (keep the default)"
      lines << "    #{ConfigAsks.dismiss_command(plastic_home, entry["id"])}"
      lines.join("\n")
    end

    [check(
      category: "config_asks", name: "pending_asks", status: "warn",
      message: "#{pending.size} pending config question(s)", details: details,
      fixable: false
    )]
  end

  # --- Check category: QMD integration (read-only, optional) ---
  #
  # QMD is an optional integration. When `qmd` is not on PATH we emit a single
  # passing check and never fail — its absence is not a Plastic health problem.
  # When present, we report whether every Plastic store is registered as a QMD
  # collection. Everything here is read-only; we never invoke a mutating qmd
  # subcommand. detector/runner are injectable so tests stay hermetic.
  def check_qmd(detector: QmdSync.method(:detect), runner: QmdSync.default_runner, collection: nil)
    return [absent_qmd_check] unless detector.call

    checks = [check(
      category: "qmd", name: "present", status: "pass",
      message: "QMD installed"
    )]

    status = QmdSync.status(plastic_home: plastic_home, runner: runner, detector: detector)
    expected = collection ? [collection] : (status[:expected] || [])
    missing = collection ? (Array(status[:missing]) & expected) : (status[:missing] || [])

    if missing.empty?
      checks << check(
        category: "qmd", name: "collections", status: "pass",
        message: collection ? "Store collection '#{collection}' registered as a QMD collection" \
                             : "All #{expected.size} Plastic store(s) registered as QMD collections"
      )
    else
      checks << check(
        category: "qmd", name: "collections", status: "warn",
        message: collection ? "Store collection '#{collection}' not registered as a QMD collection" \
                             : "#{missing.size} Plastic store(s) not registered as QMD collections",
        details: missing,
        fixable: true, fix_hint: "Run: qmd-sync register --all"
      )
    end

    checks
  end

  def absent_qmd_check
    check(
      category: "qmd", name: "present", status: "pass",
      message: "QMD not installed (optional integration)"
    )
  end

  # --- Check category: tool readiness (Serena, Enola) ---
  #
  # One readiness check per recognized code-navigation power tool (intent 221, D4). Wraps
  # PowerTools' existing pure, injectable presence detectors (scripts/lib/power_tools.rb).
  # Absence is a PASS with a note, never a warn, mirroring check_qmd's absent-is-a-silent-pass
  # shape (108 D8: power tools are recommendations, never a hard gate). No fail path exists for
  # either check: PowerTools' detectors are pure presence probes (a marker-directory walk or a
  # PATH scan) with no handshake to test whether a detected tool actually works, so there is
  # nothing to report beyond present/absent.
  def check_serena(cwd:, path_probe: PowerTools.method(:which_serena), marker_finder: PowerTools.method(:serena_marker?))
    present = PowerTools.serena?(cwd: cwd, path_probe: path_probe, marker_finder: marker_finder)

    if present
      [check(
        category: "tools", name: "serena_ready", status: "pass",
        message: "Serena is available for code navigation"
      )]
    else
      [check(
        category: "tools", name: "serena_ready", status: "pass",
        message: "Serena not installed (optional code-navigation tool)"
      )]
    end
  end

  def check_enola(cwd:, path_probe: PowerTools.method(:which_enola), marker_finder: PowerTools.method(:enola_marker?))
    present = PowerTools.enola?(cwd: cwd, path_probe: path_probe, marker_finder: marker_finder)

    if present
      [check(
        category: "tools", name: "enola_ready", status: "pass",
        message: "Enola is available for code navigation"
      )]
    else
      [check(
        category: "tools", name: "enola_ready", status: "pass",
        message: "Enola not installed (optional code-navigation tool)"
      )]
    end
  end

  # --- Check category: skill-lint (advisory only; intent 85b) ---
  #
  # Reports SkillLint's five structural checks over the skills/ tree as a
  # single ADVISORY finding. Always status: "pass", so it can never contribute
  # to doctor's warn/fail exit code (summarize buckets purely by status; the
  # lint verdict belongs to a future ship gate, intent 100, not to doctor).
  # Resolves the same repo skills/ directory `scripts/skill-lint` defaults to,
  # relative to this script's own location. Skills install flat and renamed
  # (plastic-<name>) under each agent's own skills/ dir, a different directory
  # shape SkillLint's frontmatter name-check does not target, so an installed
  # ~/.plastic/scripts/doctor.rb with no sibling skills/ tree has nothing in
  # scope here and reports a silent pass rather than guessing at a mismatched
  # layout.
  def check_skill_lint
    dir = File.expand_path("../skills", __dir__)
    unless File.directory?(dir)
      return [check(
        category: "skill_lint", name: "skill_lint", status: "pass",
        message: "No skills/ directory found at #{tilde(dir)} to lint (nothing in scope for this advisory check)"
      )]
    end

    result = SkillLint.new(skills_dir: dir).run

    if result.ok?
      [check(
        category: "skill_lint", name: "skill_lint", status: "pass",
        message: "skill-lint: clean (0 violations across the skills/ tree)"
      )]
    else
      by_check = result.violations.group_by { |v| v[:check] }.transform_values(&:size)
      counts = by_check.map { |check_id, n| "#{check_id}: #{n}" }.join(", ")
      details = result.violations.map { |v| "#{v[:check]} #{v[:skill]} #{v[:file]}:#{v[:line]}: #{v[:message]}" }
      [check(
        category: "skill_lint", name: "skill_lint", status: "pass",
        message: "skill-lint: #{result.violations.size} advisory violation(s) found (#{counts}); " \
                  "informational only, never affects doctor's exit code",
        details: details
      )]
    end
  end

  # --- Run all checks ---

  def run_checks(agent_key)
    all_checks = []
    all_checks += check_global_store
    all_checks += check_conventions(scopes: ["global"])
    all_checks += check_agent_registration(agent_key)
    all_checks += check_core_files(agent_key)
    all_checks += check_deprecations
    all_checks += check_config_asks(agent_key)
    all_checks += check_qmd
    all_checks += check_done_signals(scopes: ["global"])
    all_checks += check_skill_lint
    all_checks += check_install_integrity

    summarize(all_checks, agent_key)
  end

  # Binary core sync check: agent registration + core files (drift excluded) + manifest
  # sync + registered project paths + global store availability, rolled up with binary:
  # true so ANY warn or fail makes the overall status "fail" (and "warn" is never
  # emitted). Used by `doctor.rb --core` (219 D1/D2: operational readiness only, no
  # agent_model_drift, no store-content scanning).
  def run_core_checks(agent_key)
    all_checks = []
    all_checks += check_agent_registration(agent_key)
    all_checks += check_core_files(agent_key, include_drift: false)
    all_checks += check_manifest_sync(agent_key)
    all_checks += check_registered_project_paths
    all_checks += check_global_store_available

    summarize(all_checks, agent_key, binary: true)
  end

  # Store-scoped checks for `doctor.rb --store [global|<slug>]`.
  #   :all     -> global store + all project stores + all conventions
  #   :global  -> global store + conventions scoped to ["global"]
  #   "<slug>" -> that project only + conventions scoped to ["project:<slug>"]
  #               (fail if the slug is not registered in projects.yml)
  # 3-state roll-up (pass/warn/fail), like the full run.
  # QMD reachability is now wired into every branch, scoped to that branch's own
  # collection(s) (D3); Serena/Enola readiness is per-slug only (D4).
  def run_store_checks(store)
    all_checks =
      case store
      when :all
        check_global_store + check_project_stores + check_conventions + check_done_signals + check_qmd
      when :global
        check_global_store + check_conventions(scopes: ["global"]) +
          check_done_signals(scopes: ["global"]) + check_qmd(collection: "plastic-global")
      else
        all_checks_for_project_slug(store)
      end

    summarize(all_checks, "claude", binary: false)
  end

  # Build the checks for a single project slug, or a lone fail check when the
  # slug is unknown.
  def all_checks_for_project_slug(slug)
    projects_data = load_yaml_safe(File.join(plastic_home, "projects.yml"))
    projects = projects_data.is_a?(Hash) ? projects_data["projects"] : nil

    unless projects.is_a?(Hash) && projects.key?(slug)
      return [check(
        category: "project_stores", name: "unknown_project", status: "fail",
        message: "unknown project '#{slug}'",
        fixable: false
      )]
    end

    project_info = projects[slug]
    project_path = project_info.is_a?(Hash) ? project_info["path"] : nil
    probe_cwd = project_path || Dir.pwd

    check_project_store(slug, project_info) +
      check_conventions(scopes: ["project:#{slug}"]) +
      check_done_signals(scopes: ["project:#{slug}"]) +
      check_qmd(collection: "plastic-#{slug}") +
      check_serena(cwd: probe_cwd) +
      check_enola(cwd: probe_cwd)
  end

  # Roll a list of checks up into the standard result envelope.
  # When binary: true, the overall status is "pass" only if there are zero warn
  # AND zero fail; any warn or fail yields "fail" (never "warn"). When false
  # (the default) the classic 3-state pass/warn/fail roll-up is used.
  def summarize(all_checks, agent_key, binary: false)
    summary = { pass: 0, warn: 0, fail: 0, total: all_checks.size }
    all_checks.each { |c| summary[c[:status].to_sym] += 1 }

    overall = if binary
                (summary[:fail] > 0 || summary[:warn] > 0) ? "fail" : "pass"
              elsif summary[:fail] > 0
                "fail"
              elsif summary[:warn] > 0
                "warn"
              else
                "pass"
              end

    {
      version: read_version || "unknown",
      timestamp: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
      status: overall,
      agent: agent_key,
      checks: all_checks,
      summary: summary,
    }
  end

  # --- Main ---

  def cli(argv = ARGV)
    flags = parse_args(argv)

    if flags[:help]
      show_help
      exit 0
    end

    result =
      if !flags[:store].nil?
        run_store_checks(flags[:store])
      elsif flags[:core]
        run_core_checks(flags[:agent])
      else
        run_checks(flags[:agent])
      end

    puts JSON.pretty_generate(result)

    # --core is binary: status is only ever pass|fail, so this maps to 0|2.
    # --store and the full run keep the 3-state 0/1/2 mapping.
    case result[:status]
    when "fail" then exit 2
    when "warn" then exit 1
    else exit 0
    end
  end

end

Doctor.new(plastic_home: ENV.fetch("PLASTIC_HOME") { Doctor::DEFAULT_PLASTIC_HOME }).cli(ARGV) if $PROGRAM_NAME == __FILE__
