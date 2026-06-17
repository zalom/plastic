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

require_relative "lib/qmd_sync"
require_relative "lib/intent_validator"

# Diagnostic engine, instantiable with an injected store/agent map so tests can
# run it hermetically (no eval, no global-constant rewriting).
class Doctor
  DEFAULT_PLASTIC_HOME = File.join(Dir.home, ".plastic")

  DEFAULT_AGENTS = {
    "claude" => { name: "Claude Code", dir: File.join(Dir.home, ".claude") },
    "codex"  => { name: "Codex CLI",   dir: File.join(Dir.home, ".agents") },
    "hermes" => { name: "Hermes",      dir: File.join(Dir.home, ".hermes") },
  }.freeze

  REQUIRED_INDEX_SECTIONS = ["## Active", "## Future", "## Clusters", "## Abandoned", "## Completed"].freeze

  # Single source of truth for the required-field list lives in IntentValidator
  # (intent 60). Alias it here so the two can never drift.
  REQUIRED_FRONTMATTER_FIELDS = IntentValidator::REQUIRED_FIELDS

  CLAUDE_HOOK_SCRIPTS = %w[
    plastic-session-start
    plastic-check-update
    plastic-savepoint
    plastic-gate-check
    plastic-continue
    plastic-future-intent-check
  ].freeze

  CLAUDE_HOOK_EVENTS = %w[SessionStart PreCompact PostToolUse UserPromptSubmit].freeze

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

  attr_reader :plastic_home, :agents

  def initialize(plastic_home: DEFAULT_PLASTIC_HOME, agents: DEFAULT_AGENTS)
    @plastic_home = plastic_home
    @agents = agents
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

  def all_intent_dirs
    dirs = []

    global_store = File.join(plastic_home, "store")
    if File.directory?(global_store)
      store_intent_dirs(global_store).each do |entry|
        full = File.join(global_store, entry)
        dirs << { path: full, name: entry, scope: "global" }
      end
    end

    projects_root = File.join(plastic_home, "projects")
    if File.directory?(projects_root)
      Dir.children(projects_root).each do |project|
        project_store = File.join(projects_root, project, "store")
        next unless File.directory?(project_store)

        store_intent_dirs(project_store).each do |entry|
          full = File.join(project_store, entry)
          dirs << { path: full, name: entry, scope: "project:#{project}" }
        end
      end
    end

    dirs
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
    malformed = []
    intent_dirs.each do |d|
      md_path = File.join(d[:path], "#{d[:name]}.md")
      next unless File.exist?(md_path)

      result = IntentValidator.validate_frontmatter(parse_frontmatter(md_path))
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

    checks
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
    else
      checks += check_generic_agent_registration(agent_key, agent_dir)
    end

    checks
  end

  def check_claude_registration(agent_dir)
    checks = []
    hooks_dir = File.join(agent_dir, "hooks")

    # hooks_exist
    missing_hooks = CLAUDE_HOOK_SCRIPTS.reject { |h| File.exist?(File.join(hooks_dir, h)) }

    if missing_hooks.empty?
      checks << check(
        category: "agent_registration", name: "hooks_exist", status: "pass",
        message: "All #{CLAUDE_HOOK_SCRIPTS.size} expected hook scripts exist"
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
    existing_hooks = CLAUDE_HOOK_SCRIPTS
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
    end

    # skills_exist — flat, hyphen-namespaced personal skills (plastic-<name>/)
    checks << flat_skills_check(agent_dir, "--claude")

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

  def check_generic_agent_registration(agent_key, agent_dir)
    checks = []
    config = agents[agent_key]

    # For codex/hermes: just check skills exist (no settings.json hooks)
    checks << flat_skills_check(agent_dir, "--#{agent_key}")

    checks
  end

  # --- Check category 4: Core files ---

  def check_core_files(agent_key)
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
            fixable: false
          )
        end
      else
        checks << check(
          category: "core_files", name: "version_match", status: "warn",
          message: "Agent-side VERSION file not found at #{tilde(agent_version_path)}",
          fixable: false
        )
      end
    end

    checks
  end

  # --- Check category: manifest sync (binary core integrity) ---

  # Verify, for BOTH the global manifest and the agent-side manifest, that every
  # file listed exists and its current SHA256 matches the recorded hash.
  #   - GLOBAL manifest:    <plastic_home>/manifest.json
  #   - AGENT-side manifest: claude -> <dir>/plastic/manifest.json
  #                          other  -> <dir>/plastic-manifest.json
  # Manifest format: { "version", "created", "files": { abs_path => sha256 } }.
  # A missing manifest is a fail; any missing/mismatched listed file is a fail;
  # otherwise a single pass per manifest.
  def check_manifest_sync(agent_key)
    checks = []

    global_manifest = File.join(plastic_home, "manifest.json")
    checks << verify_manifest(global_manifest, "global")

    agent_dir = agents[agent_key][:dir]
    agent_manifest = if agent_key == "claude"
                       File.join(agent_dir, "plastic", "manifest.json")
                     else
                       File.join(agent_dir, "plastic-manifest.json")
                     end
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
        fixable: true, fix_hint: "Create project.yml from template — see plastic-creating-project"
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

  # --- Check category: QMD integration (read-only, optional) ---
  #
  # QMD is an optional integration. When `qmd` is not on PATH we emit a single
  # passing check and never fail — its absence is not a Plastic health problem.
  # When present, we report whether every Plastic store is registered as a QMD
  # collection. Everything here is read-only; we never invoke a mutating qmd
  # subcommand. detector/runner are injectable so tests stay hermetic.
  def check_qmd(detector: QmdSync.method(:detect), runner: QmdSync.default_runner)
    return [absent_qmd_check] unless detector.call

    checks = [check(
      category: "qmd", name: "present", status: "pass",
      message: "QMD installed"
    )]

    status = QmdSync.status(plastic_home: plastic_home, runner: runner, detector: detector)
    missing = status[:missing] || []

    if status[:all_registered]
      checks << check(
        category: "qmd", name: "collections", status: "pass",
        message: "All #{status[:expected].size} Plastic store(s) registered as QMD collections"
      )
    else
      checks << check(
        category: "qmd", name: "collections", status: "warn",
        message: "#{missing.size} Plastic store(s) not registered as QMD collections",
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

  # --- Run all checks ---

  def run_checks(agent_key)
    all_checks = []
    all_checks += check_global_store
    all_checks += check_conventions
    all_checks += check_agent_registration(agent_key)
    all_checks += check_core_files(agent_key)
    all_checks += check_project_stores
    all_checks += check_deprecations
    all_checks += check_qmd

    summarize(all_checks, agent_key)
  end

  # Binary core sync check: agent registration + core files + manifest sync,
  # rolled up with binary: true so ANY warn or fail makes the overall status
  # "fail" (and "warn" is never emitted). Used by `doctor.rb --core`.
  def run_core_checks(agent_key)
    all_checks = []
    all_checks += check_agent_registration(agent_key)
    all_checks += check_core_files(agent_key)
    all_checks += check_manifest_sync(agent_key)

    summarize(all_checks, agent_key, binary: true)
  end

  # Store-scoped checks for `doctor.rb --store [global|<slug>]`.
  #   :all     -> global store + all project stores + all conventions
  #   :global  -> global store + conventions scoped to ["global"]
  #   "<slug>" -> that project only + conventions scoped to ["project:<slug>"]
  #               (fail if the slug is not registered in projects.yml)
  # 3-state roll-up (pass/warn/fail), like the full run.
  def run_store_checks(store)
    all_checks =
      case store
      when :all
        check_global_store + check_project_stores + check_conventions
      when :global
        check_global_store + check_conventions(scopes: ["global"])
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

    check_project_store(slug, projects[slug]) +
      check_conventions(scopes: ["project:#{slug}"])
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

Doctor.new.cli(ARGV) if $PROGRAM_NAME == __FILE__
