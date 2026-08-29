#!/usr/bin/env ruby
# encoding: UTF-8
# frozen_string_literal: true

# Plastic doctor — diagnostic engine that checks a Plastic installation for health issues.
# Usage: ruby ~/.plastic/scripts/doctor.rb [--agent claude|codex|hermes] [--help]
#
# Output: JSON to stdout. Warnings/errors to stderr.
# Exit codes: 0 (all pass), 1 (warnings only), 2 (failures present)
# Read-only — never modifies files.

require "date"

require_relative "lib/doctor_core"

require_relative "lib/doctor_exclusions"
require_relative "lib/qmd_sync"
require_relative "lib/intent_validator"
require_relative "lib/graph_rebuild"
require_relative "lib/store_discovery"
require_relative "lib/links_projection"
require_relative "lib/links_section"
require_relative "lib/lock"
require_relative "lib/savepoint"
require_relative "lib/agent_models"
require_relative "lib/outcome_guard"
require_relative "lib/skill_lint"
require_relative "lib/config_asks"
require_relative "lib/power_tools"
require_relative "lib/preflight"
require_relative "lib/ruby_probe"

# Diagnostic engine, instantiable with an injected store/agent map so tests can
# run it hermetically (no eval, no global-constant rewriting).
# Reopens the core class defined in lib/doctor_core.rb (intent 228): that file
# holds run_core_checks and its transitive dependencies, this file adds the
# store, conventions, intent and CLI halves, so Doctor stays one class with one
# public surface.
class Doctor

  REQUIRED_INDEX_SECTIONS = ["## Active", "## Future", "## Clusters", "## Abandoned", "## Completed"].freeze

  # Single source of truth for the required-field list lives in IntentValidator
  # (intent 60). Alias it here so the two can never drift.
  REQUIRED_FRONTMATTER_FIELDS = IntentValidator::REQUIRED_FIELDS



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
    intent = nil
    disposition = nil

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
      when "--intent"
        intent = argv[i + 1]
        i += 2
      when "--disposition"
        disposition = argv[i + 1]
        i += 2
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

    { agent: agent, help: help, core: core, store: store, intent: intent, disposition: disposition }
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
        --intent ID     Per-intent structure gate at intent-end (intent 222): one
                        closing intent only, never a store sweep. Pair with
                        --store <key> to disambiguate an id that collides across
                        stores, and --disposition delivered|abandoned to fold in
                        the outcome.md disposition check. 3-state pass/warn/fail.
        -h, --help      Show this help

      Output:
        JSON to stdout with check results.
        Exit 0 = all pass, 1 = warnings only, 2 = failures present.

    HELP
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
                  "or reprojected instead); see plastic-conventions > references/maintenance-and-revisions.md"
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

# Per-directory done-signal findings for ONE intent dir (intent 222): the shared unit both
# check_done_signals's store-wide loop (211's territory, unchanged severities) and the new
# per-intent check (check_intent_end) call, so the two surfaces can never independently
# drift on what counts as a phantom line or a completeness gap. Returns
# {conflict:, phantom:, gap:, operational_gap:, excluded:, stalled:} where conflict/phantom/
# stalled are nil or a finding string, and gap/operational_gap/excluded are ARRAYs (0, 1, or 2
# strings): the original inline code pushed the "outcome missing" gap and the "audit echo
# missing" gap as two SEPARATE, independent `if` blocks (never elsif), so a single terminal
# dir missing BOTH can legitimately contribute two distinct gap strings in the same pass;
# collapsing that into one nilable field would silently drop one of the two on a dir where
# both are true (verified against test/doctor_done_signals_test.rb's fixtures before this
# extraction, per plan.md Step 3).
#
# `excluded_rules:` (intent 274) is the set of rule names the caller's doctor-exclusions file
# names for this one intent id. A savepoint_operational finding routes to :excluded instead of
# :operational_gap when "savepoint_operational" is in that set; the :gap bucket (signals_complete,
# the outcome.md check) never consults it, which is what keeps the exclusion key (intent_id,
# rule) rather than just intent_id (see test/doctor_done_signals_test.rb case 12).
#
# `:excluded_rules_fired` (intent 280) names the rules that actually suppressed a finding for
# this dir - not merely the rules registered for it. The caller uses this to build the `consumed`
# set `DoctorExclusions.dead_rows` needs: a registered rule that never fires here (nothing to
# suppress) is exactly what makes the row dead.
def done_signal_findings_for_dir(dir, label:, scope:, dirname:, terminal:, active:, excluded_rules: [])
  outcome = File.join(dir, "outcome.md")
  outcome_real = Savepoint.stage_file_present?(outcome)
  findings = { conflict: nil, phantom: nil, gap: [], operational_gap: [], excluded: [],
               excluded_rules_fired: [], stalled: nil }

  # HARD conflict: the deliverable exists but INDEX still says Active. This
  # is the one true INDEX-wins disagreement, so it stays a fail.
  if active && outcome_real
    findings[:conflict] = "#{label}: outcome.md is real but the intent is still under ## Active " \
                          "(INDEX is canonical - move it to its terminal section or revert outcome.md)"
  end

  # Savepoint truthfulness (advisory, never fail; intent 134). Terminal phantom lines are
  # ALWAYS report-only (immutable history), with no suppression by id or scope (intent 211:
  # the generic replacement for the frozen 170a amnesty list is simply "never suppress" -
  # the message already labels a terminal phantom report-only, so dropping the id-based
  # suppression is strictly more general and needs no per-store state at all).
  phantom_lines = Savepoint.savepoint_phantom_lines(dir)
  if phantom_lines.any?
    detail = phantom_lines.map { |line, reason| "#{line} (#{reason})" }.join("; ")
    scope_note = terminal ? "terminal in INDEX, report-only (immutable history)" : "live intent, auto-rebuildable"
    findings[:phantom] = "#{label}: #{phantom_lines.size} phantom savepoint line(s) contradicted by " \
                         "disk, #{scope_note}: #{detail}"
  end

  # Delivery-claim gap (intent 211, 219 D6): a missing/placeholder outcome.md on a terminal
  # intent is never fabricated, so this is unrepairable by construction. Reported informational
  # only (signals_complete, always status "pass" - see check_done_signals).
  if terminal && !outcome_real
    state = File.exist?(outcome) ? "still a placeholder" : "missing"
    findings[:gap] << "#{label}: terminal in INDEX but outcome.md is #{state} " \
                     "(delivery claim - never fabricated)"
  end

  if terminal
    # Operational gap (intent 211, 219 D6): savepoint.md missing entirely (not previously
    # checked at all) or present but missing the Done bookend - both are minimally
    # reconstructible via maintenance-run --tool rebuild-savepoint, so this is repairable and
    # reported as a fixable warn (savepoint_operational).
    savepoint = File.join(dir, "savepoint.md")
    suppressed = excluded_rules.include?("savepoint_operational")
    bucket = suppressed ? findings[:excluded] : findings[:operational_gap]
    if !File.exist?(savepoint)
      bucket << "#{label}: terminal in INDEX but savepoint.md is missing " \
                "entirely (operational - reconstructible)"
    elsif File.read(savepoint) !~ /\bDone\b.*\b(delivered|abandoned)\b/
      bucket << "#{label}: terminal in INDEX but savepoint.md has no " \
                "`Done delivered|abandoned` line (operational - reconstructible)"
    end
    findings[:excluded_rules_fired] << "savepoint_operational" if suppressed && findings[:excluded].any?

    # Stalled completion: unchanged, never consulted amnesty.
    if File.exist?(Lock.path(dir))
      note = Lock.fresh?(dir) ? "delivery.lock still present (post-done window not closed)"
                              : "delivery.lock is present and STALE"
      findings[:stalled] = "#{label}: #{note} - the End tail did not finish"
    end
  end

  findings
end

def check_done_signals(scopes: nil)
  conflicts = []
  gaps = []              # delivery-claim (outcome.md) gaps only - legacy, informational
  operational_gaps = []  # savepoint gaps (missing file, or missing Done echo) - repairable
  excluded = []           # savepoint gaps knowingly exempted via doctor-exclusions (intent 274)
  exclusion_errors = []   # malformed doctor-exclusions lines, scope-tagged
  exclusion_error_paths = []
  exclusion_paths = []    # files that actually contributed a live exclusion
  dead_rows = []          # exclusion rows that suppressed nothing this run (intent 280)
  dead_row_paths = []
  stalled = []
  phantoms = []

  done_signal_stores(scopes).each do |store|
    exclusions = DoctorExclusions.load(store[:index])
    if exclusions[:errors].any?
      exclusion_errors.concat(exclusions[:errors].map { |e| "#{store[:scope]}: #{e}" })
      exclusion_error_paths << exclusions[:path]
    end

    consumed = { "savepoint_operational" => [] }
    # `known_ids` (post-review fix): every intent id with a REAL DIRECTORY in this store, scanned
    # directly from disk - independent of INDEX.md. An id can have a directory on disk without
    # being listed in INDEX (a de-indexed "ghost"), and the walk below alone would never visit it;
    # deriving known_ids from walk membership misclassified that ghost as :no_intent (deleted)
    # even though the directory plainly still exists.
    # Shares `store_intent_dirs` (159, intent 189's store-discovery helper) rather than
    # reimplementing the same directory scan (review fix): one predicate for "what is an intent
    # directory in this store", never two that could drift apart.
    known_ids = if File.directory?(store[:store_dir])
                  store_intent_dirs(store[:store_dir]).map { |e| e.split("--", 2).first }
                else
                  []
                end
    # `evaluated_ids`: the narrower set the walk below actually judges (INDEX-listed and on
    # disk). An id with a real directory that this run never evaluated (on disk, unindexed)
    # carries no evidence either way and must never be called dead - dead_rows leaves it out.
    evaluated_ids = []

    index_sections_by_dir(store[:index]).each do |dirname, in_sections|
      dir = File.join(store[:store_dir], dirname)
      next unless File.directory?(dir)

      terminal = (in_sections & ["Completed", "Abandoned"]).any?
      active = in_sections.include?("Active") && !terminal
      label = "#{store[:scope]} store/#{dirname}"
      intent_id = dirname.split("--", 2).first
      evaluated_ids << intent_id
      excluded_rules = DoctorExclusions.rules_for(exclusions, intent_id)

      findings = done_signal_findings_for_dir(
        dir, label: label, scope: store[:scope], dirname: dirname, terminal: terminal, active: active,
        excluded_rules: excluded_rules
      )
      conflicts << findings[:conflict] if findings[:conflict]
      phantoms << findings[:phantom] if findings[:phantom]
      gaps.concat(findings[:gap])
      operational_gaps.concat(findings[:operational_gap])
      if findings[:excluded].any?
        excluded.concat(findings[:excluded])
        exclusion_paths << exclusions[:path]
      end
      findings[:excluded_rules_fired].each { |fired| (consumed[fired] ||= []) << intent_id }
      stalled << findings[:stalled] if findings[:stalled]
    end

    # Drift in the governance record itself (intent 280): rows naming a pair that produced no
    # finding this run. Computed by set subtraction against the walk above, never re-derived from
    # the exclusion file (208; the intent 200 self-diff). `:no_intent` below only ever fires when
    # `known_ids` (a real directory scan) truly has no entry for the id - never merely because the
    # walk did not visit it.
    DoctorExclusions.dead_rows(exclusions, consumed: consumed, known_ids: known_ids,
                                evaluated_ids: evaluated_ids).each do |row|
      reason = if row[:reason] == :no_intent
                 "names no live intent directory (a typo, or the intent was deleted)"
               else
                 "names an intent with no current #{row[:rule]} finding"
               end
      dead_rows << "#{store[:scope]}: #{exclusions[:path]}: #{row[:rule]} #{row[:id]} - #{reason}"
      dead_row_paths << exclusions[:path]
    end
  end
  exclusion_paths.uniq!
  exclusion_error_paths.uniq!
  dead_row_paths.uniq!

  checks = []

  # signals_agree: unchanged.
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

  # signals_complete (intent 211, 219 D6, repurposed): outcome.md delivery-claim gaps only.
  # Never fabricated, so there is no legitimate fix to hint at - always status "pass",
  # informational (matches check_skill_lint's advisory precedent: count + details, no
  # fix_hint/fixable, never affects doctor's exit code).
  if gaps.empty?
    checks << check(
      category: "done_signals", name: "signals_complete", status: "pass",
      message: "Every terminal intent carries a real outcome.md"
    )
  else
    checks << check(
      category: "done_signals", name: "signals_complete", status: "pass",
      message: "#{gaps.size} terminal intent#{gaps.size == 1 ? "" : "s"} missing a real outcome.md " \
               "(delivery claim - never fabricated; informational only, does not affect doctor's exit code)",
      details: gaps
    )
  end

  # savepoint_operational (intent 211; intent 274 adds the per-store doctor-exclusions index):
  # missing savepoint.md or missing Done echo - repairable via maintenance-run --tool
  # rebuild-savepoint for most gaps, or knowingly excluded for the ones 219 D6 forbids ever
  # repairing (no real outcome.md to echo a disposition from). Three branches (spec D4/D5):
  # a malformed exclusion file can never report pass (loud), a clean remaining gap set reports
  # pass with the exclusion count folded in, and a real remaining gap set stays warn, same as
  # before intent 274, with the same count folded in when exclusions applied.
  #
  # `dead_suffix` (intent 280) folds in a second, independent drift notice: exclusion rows that
  # suppressed nothing this run. It is purely informational, exactly like `exclusion_suffix` - it
  # never changes status on any of the three branches below, because a stale governance-record row
  # is bookkeeping drift, not a store regression (219 D6 is untouched: no disposition is invented).
  exclusion_suffix = excluded.empty? ? "" : " (#{excluded.size} excluded via #{exclusion_paths.join(", ")})"
  dead_suffix = dead_rows.empty? ? "" : " (#{dead_rows.size} dead row#{dead_rows.size == 1 ? "" : "s"} " \
                                        "in #{dead_row_paths.join(", ")}, suppressing nothing - prune with " \
                                        "`maintenance-run --tool register-exclusions --prune`)"

  if exclusion_errors.any?
    checks << check(
      category: "done_signals", name: "savepoint_operational", status: "warn",
      message: "#{operational_gaps.size} terminal intent#{operational_gaps.size == 1 ? "" : "s"} " \
               "missing an operational savepoint.md or its Done echo, and " \
               "#{exclusion_errors.size} doctor-exclusions error#{exclusion_errors.size == 1 ? "" : "s"} " \
               "(a malformed exclusion file never suppresses a finding)#{exclusion_suffix}#{dead_suffix}",
      details: operational_gaps + exclusion_errors + dead_rows, fixable: true,
      fix_hint: "Fix the malformed doctor-exclusions file(s) (#{exclusion_error_paths.join(", ")}) - " \
                "format `rule_name id id id`, blank lines and # comments ignored - then reconstruct " \
                "any remaining real gap via `maintenance-run --tool rebuild-savepoint --intent <id> " \
                "--apply` (197-conformant: receipt-before-write via RevisionsWriter, one intent per " \
                "invocation, owner-approval-gated)."
    )
  elsif operational_gaps.empty?
    checks << check(
      category: "done_signals", name: "savepoint_operational", status: "pass",
      message: "No terminal intent is missing an operational savepoint.md or its Done echo" \
               "#{exclusion_suffix}#{dead_suffix}",
      details: dead_rows
    )
  else
    checks << check(
      category: "done_signals", name: "savepoint_operational", status: "warn",
      message: "#{operational_gaps.size} terminal intent#{operational_gaps.size == 1 ? "" : "s"} " \
               "missing an operational savepoint.md or its Done echo (reconstructible)" \
               "#{exclusion_suffix}#{dead_suffix}",
      details: operational_gaps + dead_rows, fixable: true,
      fix_hint: "Reconstruct the minimal two-line started/Done echo via " \
                "`maintenance-run --tool rebuild-savepoint --intent <id> --apply` (197-conformant: " \
                "receipt-before-write via RevisionsWriter, one intent per invocation, owner-approval-gated)."
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

  # savepoint_truthful: advisory only (intent 134), never fails. No amnesty suppression left.
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
                "Savepoint.rebuild_savepoint. Terminal (Completed/Abandoned) intents are immutable: " \
                "a phantom there stays advisory unless an explicit human grant authorizes the " \
                "124a manual Done-bookend repair."
    )
  end

  checks
end

  # Build the cross-store node maps (basename + label per store) + relocation map from ALL
  # stores (intent 222): the one shared build both the store-wide links_projection_check and
  # the new per-intent intent_links_projection_check_for call, so the two can never disagree
  # on how a ref resolves.
  def build_links_projection_context
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
    { store_index: store_index, node_index: node_index, relocation_map: relocation_map, intents: intents }
  end

  # Build the cross-store node maps (basename + label per store) + relocation map
  # from ALL stores, then for every intent compute its canonical `## Links`
  # projection and flag any whose ACTUAL `## Links` section differs (membership or
  # ordering drift), or whose projection raises UnresolvedRef. `scopes` (nil = full
  # run) filters only the REPORTED findings by origin scope.
  def links_projection_check(scopes: nil)
    ctx = build_links_projection_context
    store_index = ctx[:store_index]
    node_index = ctx[:node_index]
    relocation_map = ctx[:relocation_map]
    intents = ctx[:intents]

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
      "(plastic-conventions > references/maintenance-and-revisions.md)."
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

  # --- Check scope 4: per-intent structure gate at intent-end (intent 222) ---
  #
  # Doctor's fourth check scope, invoked by `--intent <id>`. Never a store-wide sweep:
  # resolves exactly one intent directory (mirrors scripts/end-intent's resolve_intent_dir /
  # scripts/project-links's --intent disambiguation) and returns five checks, four
  # FAIL-severity, one WARN-severity (intent_savepoint_truthful stays WARN per intent 134's
  # binding advisory-only ruling; see spec.md D2/D8 - do NOT escalate it to FAIL).
  def check_intent_end(id, store: nil, disposition: nil)
    intent_dir, scope = resolve_single_intent_dir(id, store: store)
    unless intent_dir
      return [check(
        category: "intent_end", name: "intent_resolved", status: "fail",
        message: "no intent directory matches #{id.inspect}" \
                 "#{store ? " under store #{store.inspect}" : ""}"
      )]
    end

    # The owning store's INDEX.md, resolved from `scope` through the memoized store_discovery
    # (same {key:, index:} shape done_signal_stores enumerates). intent_savepoint_truthful_check
    # needs it to reach that store's doctor-exclusions table and to ask INDEX whether this
    # intent is terminal (intent 281 D3/D6). nil when the scope resolves to no known store,
    # which restores the pre-281 behavior exactly.
    index_path = store_discovery[:stores].find { |s| s[:key] == scope }&.fetch(:index, nil)

    [
      intent_structure_check(intent_dir),
      intent_lifecycle_artifacts_check(intent_dir, disposition),
      intent_checklist_complete_check(intent_dir),
      intent_links_projection_check_for(id, scope),
      intent_savepoint_truthful_check(intent_dir, index_path: index_path),
    ]
  end

  # Resolves --intent (+ optional --store) to exactly one (intent_dir, scope) pair, or
  # [nil, nil] when found nowhere. `store`, when given, must already be a resolved scope key
  # (e.g. "global" or "project:<slug>", matching all_intent_dirs' own `d[:scope]`); the CLI
  # boundary (`cli`) is what translates the loosely-typed --store flag value into this shape.
  # Aborts loud (raises) on cross-store ambiguity when no scope was given, mirroring
  # scripts/project-links's resolve_target_store.
  def resolve_single_intent_dir(id, store: nil)
    candidates = all_intent_dirs.select { |d| d[:name].start_with?("#{id}--") }
    candidates = candidates.select { |d| d[:scope] == store } if store

    return [nil, nil] if candidates.empty?
    if candidates.length > 1
      scopes = candidates.map { |d| d[:scope] }.join(", ")
      raise "intent #{id.inspect} is ambiguous across stores (#{scopes}); pass --store <key> " \
            "to disambiguate (e.g. --store #{candidates.first[:scope]})"
    end

    [candidates.first[:path], candidates.first[:scope]]
  end

  def intent_structure_check(intent_dir)
    result = IntentValidator.validate(intent_dir)
    if result[:ok]
      check(category: "intent_end", name: "intent_structure", status: "pass",
            message: "Intent file frontmatter and sections are well-formed")
    else
      check(category: "intent_end", name: "intent_structure", status: "fail",
            message: "Intent file has #{result[:errors].size} structural error(s)",
            details: result[:errors])
    end
  end

  INTENT_END_LIFECYCLE_FILES = %w[spec.md plan.md checklist.md outcome.md].freeze

  def intent_lifecycle_artifacts_check(intent_dir, disposition)
    missing = INTENT_END_LIFECYCLE_FILES.select { |f| !Savepoint.stage_file_present?(File.join(intent_dir, f)) }
    unless Savepoint.stage_file_present?(Savepoint.intent_file(intent_dir))
      missing = [File.basename(Savepoint.intent_file(intent_dir))] + missing
    end

    outcome_note = nil
    if disposition && !missing.include?("outcome.md")
      outcome_note = OutcomeGuard.reason(intent_dir, disposition)
    end

    if missing.empty? && outcome_note.nil?
      check(category: "intent_end", name: "intent_lifecycle_artifacts", status: "pass",
            message: "Every lifecycle artifact is present and real")
    else
      details = missing.map { |f| "#{f} missing or still a placeholder" }
      details << outcome_note if outcome_note
      check(category: "intent_end", name: "intent_lifecycle_artifacts", status: "fail",
            message: "#{details.size} lifecycle-artifact gap(s)", details: details)
    end
  end

  def intent_checklist_complete_check(intent_dir)
    path = File.join(intent_dir, "checklist.md")
    unless Savepoint.stage_file_present?(path)
      return check(category: "intent_end", name: "intent_checklist_complete", status: "pass",
                    message: "n/a: checklist.md absent or placeholder (flagged above if that is a gap)")
    end

    unchecked = File.read(path).scan(/^- \[ \].*$/)
    if unchecked.empty?
      check(category: "intent_end", name: "intent_checklist_complete", status: "pass",
            message: "checklist.md has zero unchecked items")
    else
      check(category: "intent_end", name: "intent_checklist_complete", status: "fail",
            message: "#{unchecked.size} unchecked checklist item(s) remain", details: unchecked)
    end
  end

  def intent_links_projection_check_for(id, scope)
    ctx = build_links_projection_context
    node = ctx[:intents].find { |n| n[:id] == id && n[:scope] == scope }
    unless node
      return check(category: "intent_end", name: "intent_links_projection", status: "warn",
                    message: "could not locate #{id.inspect} in the links-projection graph")
    end

    resolve = ->(ref) do
      LinksProjection.resolve_ref_projection(
        ref, referer_store: node[:scope], relocation_map: ctx[:relocation_map],
             store_index: ctx[:store_index], node_index: ctx[:node_index]
      )
    end

    begin
      expected = LinksProjection.section(sources: node[:sources], chain: node[:chain], resolve: resolve)
      actual = actual_links_section(node[:path])
    rescue LinksProjection::UnresolvedRef, LinksSection::AmbiguousLinks => e
      return check(category: "intent_end", name: "intent_links_projection", status: "fail",
                    message: "## Links projection failed: #{e.message}")
    end

    if actual == expected
      check(category: "intent_end", name: "intent_links_projection", status: "pass",
            message: "## Links matches its frontmatter projection")
    else
      check(category: "intent_end", name: "intent_links_projection", status: "fail",
            message: "## Links does not match its frontmatter projection (membership/ordering drift)",
            fixable: true,
            fix_hint: "Run scripts/project-links --intent #{id} --apply (via maintenance-run)")
    end
  end

  # Whether this one intent's missing-savepoint finding is knowingly excluded, for the
  # per-intent surface (intent 281). Returns {excluded:, errors:, path:}.
  #
  # Same rule id as the store-wide sweep, `savepoint_operational` (281 D1): the fact is
  # identical (a terminal intent with no savepoint.md), so one registration in one
  # doctor-exclusions file covers both surfaces and the owner never learns a second name for
  # one gap. RuleCatalog is deliberately NOT extended.
  #
  # Terminal-gated (281 D3): done_signal_findings_for_dir only ever produces this finding
  # inside `if terminal`, so honoring the exclusion for a still-Active intent would suppress a
  # strictly larger set of facts than the rule id names - and would let a mistyped id silence
  # the live, repairable warning scripts/end-intent's pre-write gate exists to raise.
  #
  # Never raises: DoctorExclusions is fail-open by contract (274 D5) and index_sections_by_dir
  # returns an empty map for a missing INDEX.
  def savepoint_exclusion_for(intent_dir, index_path)
    none = { excluded: false, errors: [], path: nil }
    return none unless index_path

    dirname = File.basename(intent_dir)
    return none unless (index_sections_by_dir(index_path)[dirname] & ["Completed", "Abandoned"]).any?

    loaded = DoctorExclusions.load(index_path)
    rules = DoctorExclusions.rules_for(loaded, dirname.split("--", 2).first)
    { excluded: rules.include?("savepoint_operational"), errors: loaded[:errors], path: loaded[:path] }
  end

  # WARN-only, per intent 134 (savepoint truthfulness is advisory, never a hard gate). Do not
  # change this to FAIL: it would silently contradict a standing, binding ruling.
  #
  # `index_path:` (intent 281) is the owning store's INDEX.md, threaded from check_intent_end.
  # It makes this surface honor the same doctor-exclusions registration check_done_signals
  # already honors for the same fact, under the same rule id (281 D1). Only the missing-file
  # branch below is excludable: the phantom-line branch is permanently non-suppressible by id
  # or scope (intent 211, 281 D2). Omitting index_path restores the pre-281 behavior exactly.
  def intent_savepoint_truthful_check(intent_dir, index_path: nil)
    savepoint = File.join(intent_dir, "savepoint.md")
    unless File.exist?(savepoint)
      exclusion = savepoint_exclusion_for(intent_dir, index_path)

      # A loader error never suppresses anything (274 D5: fail milder than the bug), and the
      # check that consulted the file is where the error is reported.
      if exclusion[:errors].any?
        return check(
          category: "intent_end", name: "intent_savepoint_truthful", status: "warn",
          message: "savepoint.md is missing, and #{exclusion[:errors].size} doctor-exclusions " \
                   "error#{exclusion[:errors].size == 1 ? "" : "s"} " \
                   "(a malformed exclusion file never suppresses a finding)",
          details: exclusion[:errors], fixable: true,
          fix_hint: "Fix the malformed doctor-exclusions file (#{exclusion[:path]}) - format " \
                    "`rule_name id id id`, blank lines and # comments ignored - then re-run."
        )
      end

      # Excluded: the fact stays in the message with the honest count and the file that caused
      # the suppression, and nothing lands in details (274 D4's wording, N is always 1 here).
      if exclusion[:excluded]
        return check(category: "intent_end", name: "intent_savepoint_truthful", status: "pass",
                     message: "savepoint.md is missing (1 excluded via #{exclusion[:path]})")
      end

      return check(category: "intent_end", name: "intent_savepoint_truthful", status: "warn",
                    message: "savepoint.md is missing")
    end

    first_line = File.read(savepoint).each_line.find { |l| !l.strip.empty? }.to_s.strip
    parts = first_line.split(/\s{2,}/)
    born_pair = parts.length >= 3 ? [parts[1], parts[2]] : nil
    expected_pair = Savepoint.savepoint_milestone(intent_dir, File.basename(Savepoint.intent_file(intent_dir)))

    phantoms = Savepoint.savepoint_phantom_lines(intent_dir)
    problems = []
    problems << "born line #{born_pair.inspect} does not match the expected #{expected_pair.inspect}" \
      if born_pair != expected_pair
    problems << "#{phantoms.size} phantom savepoint line(s): " \
                "#{phantoms.map { |l, r| "#{l} (#{r})" }.join("; ")}" if phantoms.any?

    if problems.empty?
      check(category: "intent_end", name: "intent_savepoint_truthful", status: "pass",
            message: "Savepoint born line and phantom-line state are truthful")
    else
      check(category: "intent_end", name: "intent_savepoint_truthful", status: "warn",
            message: "#{problems.size} savepoint truthfulness issue(s) (advisory, never blocking)",
            details: problems,
            fixable: true, fix_hint: "Run plastic-intent-savepoint to rebuild via Savepoint.rebuild_savepoint")
    end
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
      "plastic-conventions > references/maintenance-and-revisions.md), or restore the missing intent"
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



  # Plastic skills install as ~/.claude/skills/plastic-<name>/SKILL.md. Pass if at
  # least one such skill is present.

  # Backstop for a rename or removal (intent 158a, AC15): an installed plastic-*
  # skill directory under agent_dir/skills that has NO corresponding entry in the
  # current install manifest is a stray (e.g. a leftover old-name copy the
  # install/update prune should have removed, or one it never saw because the
  # manifest predates it). Complements flat_skills_check (which only confirms at
  # least one skill exists). Defers to the manifest check when the manifest itself
  # is missing or malformed, so the two checks never double-report the same gap.

  # Auto-mode role agents install as <dir>/agents/plastic-*.md. Pass if at least
  # one such role file is present (the installer syncs agents/ on every install).

  # Shared skills-presence plus stray-skills check, used by both the generic
  # (hermes) agent-registration path and codex's TOML-based one. Neither the flat
  # `.md` agents check nor anything agent-format-specific lives here.


  # Plain string extraction of the two model-selection lines a generated
  # Codex agent TOML can carry, read separately (intent 216). Per the
  # emission contract in installer_core.rb's codex_model_fields: a tier
  # alias emits BOTH `model` and `model_reasoning_effort` (model first); a
  # literal Codex model id override emits `model` only, no effort line; an
  # empty value emits neither. No TOML parser dependency, mirroring
  # codex_agent_toml_well_formed? above.
  #
  # Regex detail: `/^model\s*=\s*"([^"]*)"/` cannot match a
  # `model_reasoning_effort = "..."` line, because the character right
  # after `model` there is `_`, which matches neither `\s` nor `=`. The two
  # matchers are independent lookups and need no ordering trick, unlike the
  # single-value extractor this replaces. `^` anchors at line start in
  # Ruby by default, so no `/m` flag is needed.
  def codex_agent_toml_model_fields(content)
    model = content.match(/^model\s*=\s*"([^"]*)"/)
    effort = content.match(/^model_reasoning_effort\s*=\s*"([^"]*)"/)
    { model: model && model[1], effort: effort && effort[1] }
  end

  # codex_hooks_registered (intent 102, the owner-facing first-run validation
  # path, Decision 14): ~/.codex/hooks.json must carry EXACTLY the commands
  # HookRegistry.codex_hooks_json defines, mirroring the Claude
  # hooks_match_registry diff. Never writes.

  # Source-text extraction of scripts/codex-hook's supported gate names (D3): the
  # dispatcher is an executable script with real top-level side effects (it reads
  # $stdin and may exit), so it can never be required or executed to introspect it,
  # only read as plain text, mirroring codex_agent_toml_well_formed? above. Pulls
  # hook names from the STATE_HOOKS %w[] literal, plus the `when
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

  # config.toml advisory (intent 102, Decision 2, R2): READ ONLY. Warns on the two
  # documented footguns (hooks disabled, sandbox read-only); never writes, and
  # returns nil (no check emitted) when config.toml is absent or carries neither.

  # --- Check category 4: Core files ---


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

  # Codex leg of agent_model_drift (intent 198, Decision D4; widened intent
  # 216 to cover both TOML lines). The shared .md path above is structurally
  # blind on Codex (codex agents are TOML under ~/.codex/agents/, never
  # ~/.agents/agents/*.md), so it always passed on an empty glob without
  # opening a single Codex file. This mirrors the same four buckets
  # (sanctioned override, matches default, drifted, unclassified) against
  # ~/.codex/agents/plastic-*.toml instead, reading `model` and
  # `model_reasoning_effort` as two SEPARATE lines via
  # codex_agent_toml_model_fields, the same plain string matching
  # codex_agent_toml_well_formed? already uses (no TOML parser dependency).
  #
  # Per the intent-186 emission contract (installer_core.rb's
  # codex_model_fields): a tier alias writes BOTH lines, a literal Codex
  # model id override writes `model` only. Bucket 2 (no override, basename
  # is a TIER_DEFAULTS key) therefore compares BOTH fields, each against its
  # own config-resolved default: the model value against
  # AgentModels.codex_model_for(tier), the effort value against
  # AgentModels.effort_for(tier), honoring the Codex-scoped
  # agents.models.codex.<name> override precedence install_codex's own
  # agent_model_overrides(harness: "codex") already applies. Either field
  # disagreeing is drift; the detail line names exactly which field(s)
  # drifted so a model mismatch never reads as an effort mismatch or vice
  # versa. An alias with no mapped Codex model id (codex_model_for returns
  # nil) skips the model comparison rather than reporting drift, mirroring
  # the installer, which still emits the effort line alone in that case.
  #
  # Bucket 1 (an agents.models.codex.<name> override is configured) stays
  # sanctioned and is NEVER compared: per-agent model and effort are user
  # configuration, per harness and per project, and can be edited after
  # install without a reinstall, so an override must always read as
  # healthy. This also keeps the Codex leg identical in shape to the Claude
  # leg's four-bucket contract from intent 191.
  #
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
      fields = codex_agent_toml_model_fields(File.read(path))
      override = overrides[basename]

      if override
        sanctioned << "#{basename}: toml model=#{fields[:model].inspect}, " \
                      "toml effort=#{fields[:effort].inspect}, sanctioned override=#{override.inspect}"
      elsif AgentModels::TIER_DEFAULTS.key?(basename)
        tier = AgentModels::TIER_DEFAULTS[basename]
        expected_model = AgentModels.codex_model_for(tier)
        expected_effort = AgentModels.effort_for(tier)
        mismatches = []
        if expected_model && fields[:model] != expected_model
          mismatches << "model=#{fields[:model].inspect}, resolved default model=#{expected_model.inspect}"
        end
        if expected_effort && fields[:effort] != expected_effort
          mismatches << "effort=#{fields[:effort].inspect}, resolved default effort=#{expected_effort.inspect}"
        end
        drifted << "#{basename}: #{mismatches.join("; ")}" if mismatches.any?
      else
        unclassified << "#{basename}: toml model=#{fields[:model].inspect}, " \
                        "toml effort=#{fields[:effort].inspect}, no resolved default (basename is in " \
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
      parts << "#{drifted.size} installed Codex agent TOML(s) have unsanctioned model or effort drift vs the config-resolved default" if drifted.any?
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

  # --- Check category: runtime (which ruby a spawned hook resolves) ---
  #
  # Intent 235, D6. REPORT ONLY: this check never pins an interpreter and never repairs.
  # A hook is launched by the agent application, not by a login shell, so a version
  # manager that activates on shell prompt render (mise, rbenv, asdf) may never reach it
  # and bare `ruby` can still resolve to the system interpreter long after the user
  # installs a modern Ruby.
  #
  # Below the floor is a WARN, never a fail. Doctor cannot know that the PATH it sees is
  # the PATH the agent application will hand its hooks, so it reports the risk with a
  # precise fix hint instead of blocking. "Could not determine" is the same warn: an
  # honest unknown, not a silent pass.
  #
  # The probe is injected as a keyword with a real default (see check_serena for the same
  # shape), so tests never spawn a process and never touch ENV.
  def check_ruby_runtime(probe: RubyProbe.method(:resolve))
    resolved = probe.call
    version = resolved[:version]
    parsed = version && safe_version(version)

    if parsed.nil?
      return [check(
        category: "runtime", name: "ruby_floor", status: "warn",
        message: "Could not determine which ruby a Plastic hook would resolve on PATH " \
                 "(no runnable `ruby` answered), so Plastic cannot confirm hook processes " \
                 "meet the Ruby #{Preflight::RUBY_FLOOR} floor",
        fixable: false,
        fix_hint: "Make sure `ruby -v` works, then pin one for the whole machine: " \
                  "mise use --global ruby@#{Preflight::RUBY_PIN}"
      )]
    end

    where = resolved[:path].to_s.empty? ? "ruby on PATH" : resolved[:path]

    if parsed < safe_version(Preflight::RUBY_FLOOR)
      return [check(
        category: "runtime", name: "ruby_floor", status: "warn",
        message: "Hooks would resolve Ruby #{version} at #{where}, below Plastic's floor of " \
                 "#{Preflight::RUBY_FLOOR}. Hook scripts can fail on this interpreter even when " \
                 "your own shell has a newer Ruby, because a shell-activated version manager " \
                 "does not reach a hook process spawned by the agent application",
        details: [where],
        fixable: false,
        fix_hint: "Pin a Ruby the whole machine sees: mise use --global ruby@#{Preflight::RUBY_PIN}"
      )]
    end

    [check(
      category: "runtime", name: "ruby_floor", status: "pass",
      message: "Hooks would resolve Ruby #{version} at #{where}, at or above Plastic's floor " \
               "of #{Preflight::RUBY_FLOOR}",
      details: [where]
    )]
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
    all_checks += check_ruby_runtime
    all_checks += check_done_signals(scopes: ["global"])
    all_checks += check_skill_lint
    all_checks += check_install_integrity

    summarize(all_checks, agent_key)
  end

  # Per-intent structure gate for `doctor.rb --intent <id> [--store <key>] [--disposition ...]`
  # (intent 222). `store`, here, is already the resolved scope key (see
  # normalize_intent_store_scope, the CLI-boundary translator that turns the loosely-typed
  # --store flag value into this shape before calling in).
  def run_intent_check(id, store: nil, disposition: nil)
    checks = check_intent_end(id, store: store, disposition: disposition)
    summarize(checks, "claude", binary: false)
  end

  # Translate the loosely-typed --store flag value (nil / :all / :global / a bare project
  # slug String, see parse_args) into the scope-key shape all_intent_dirs' own `d[:scope]`
  # uses ("global" / "project:<slug>"), for --intent disambiguation only. --store with no
  # value (:all) means "no disambiguation given" here, distinct from its store-scan meaning.
  def normalize_intent_store_scope(store)
    case store
    when nil, :all then nil
    when :global then "global"
    else "project:#{store}"
    end
  end

  # Store-scoped checks for `doctor.rb --store [global|<slug>]`.
  #   :all     -> global store + all project stores + all conventions
  #   :global  -> global store + conventions scoped to ["global"]
  #   "<slug>" -> that project only + conventions scoped to ["project:<slug>"]
  #               (fail if the slug is not registered in projects.yml)
  # 3-state roll-up (pass/warn/fail), like the full run.
  # QMD reachability is now wired into every branch, scoped to that branch's own
  # collection(s) (D3); Serena/Enola readiness is per-slug only (D4).
  # Same injection seams as all_checks_for_project_slug (intent 221a), threaded through
  # so every branch's check_qmd/check_serena/check_enola call can be made hermetic.
  # Defaults are byte-identical to the real probes; both production callers
  # (scripts/doctor.rb's CLI entry point and scripts/dashboard.rb) call
  # run_store_checks(store) with a single positional argument and no kwargs, so
  # behavior at those call sites is unchanged.
  def run_store_checks(store, qmd_detector: QmdSync.method(:detect), qmd_runner: QmdSync.default_runner,
                        serena_path_probe: PowerTools.method(:which_serena),
                        serena_marker_finder: PowerTools.method(:serena_marker?),
                        enola_path_probe: PowerTools.method(:which_enola),
                        enola_marker_finder: PowerTools.method(:enola_marker?))
    all_checks =
      case store
      when :all
        check_global_store + check_project_stores + check_conventions + check_done_signals +
          check_qmd(detector: qmd_detector, runner: qmd_runner)
      when :global
        check_global_store + check_conventions(scopes: ["global"]) +
          check_done_signals(scopes: ["global"]) +
          check_qmd(detector: qmd_detector, runner: qmd_runner, collection: "plastic-global")
      else
        all_checks_for_project_slug(store, qmd_detector: qmd_detector, qmd_runner: qmd_runner,
                                     serena_path_probe: serena_path_probe, serena_marker_finder: serena_marker_finder,
                                     enola_path_probe: enola_path_probe, enola_marker_finder: enola_marker_finder)
      end

    summarize(all_checks, "claude", binary: false)
  end

  # Build the checks for a single project slug, or a lone fail check when the
  # slug is unknown.
  # qmd_detector/qmd_runner and the serena_/enola_ path_probe/marker_finder kwargs are
  # injection seams (intent 221a) mirroring check_qmd/check_serena/check_enola's own
  # kwargs, defaulted to the same real probes those methods already default to. No
  # caller passes these; they exist so tests can make host state (QMD/Serena/Enola
  # presence) irrelevant.
  def all_checks_for_project_slug(slug, qmd_detector: QmdSync.method(:detect), qmd_runner: QmdSync.default_runner,
                                   serena_path_probe: PowerTools.method(:which_serena),
                                   serena_marker_finder: PowerTools.method(:serena_marker?),
                                   enola_path_probe: PowerTools.method(:which_enola),
                                   enola_marker_finder: PowerTools.method(:enola_marker?))
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
      check_qmd(detector: qmd_detector, runner: qmd_runner, collection: "plastic-#{slug}") +
      check_serena(cwd: probe_cwd, path_probe: serena_path_probe, marker_finder: serena_marker_finder) +
      check_enola(cwd: probe_cwd, path_probe: enola_path_probe, marker_finder: enola_marker_finder)
  end


  # --- Main ---

  def cli(argv = ARGV)
    flags = parse_args(argv)

    if flags[:help]
      show_help
      exit 0
    end

    result =
      if flags[:intent]
        begin
          run_intent_check(flags[:intent], store: normalize_intent_store_scope(flags[:store]),
                                            disposition: flags[:disposition])
        rescue StandardError => e
          $stderr.puts "doctor: #{e.message}"
          exit 2
        end
      elsif !flags[:store].nil?
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
