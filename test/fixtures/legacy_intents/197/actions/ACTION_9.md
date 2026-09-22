# ACTION_9 - new CLI: scripts/maintenance-run

Depends on ACTION_1 (`project-links --intent`), ACTION_2 (malformed-orphan reporting, along
for the ride), ACTION_4 (`project-links` writes receipts), ACTION_5 (`rebuild-graph` writes
receipts), ACTION_8 (`MaintenanceGit`). This is the tool that composes everything above into
one operable maintenance path: detect-only lock check (never acquire), then
`MaintenanceGit.run_scoped` isolation around the real tool invocation. Covers the "Plan where
this lives" half of the dispatch brief's maintenance task, for the three CODE tools (the
curator's own hand-run equivalent is ACTION_7).

File: new `scripts/maintenance-run` (inside the worktree).

## 9a. The CLI

```ruby
#!/usr/bin/env ruby
# encoding: UTF-8
# frozen_string_literal: true

# maintenance-run - the maintenance dispatch wrapper (intent 197). DETECTS (never acquires) a
# target intent's delivery lock (Lock.fresh?) and defers if fresh; otherwise runs the
# requested tool inside MaintenanceGit.run_scoped so the change and its revisions.md receipt
# land as ONE scoped, merged commit on the store's own main, never via `git add -A`.
#
# Dry-run by DEFAULT (mirrors restore-intent-v1's higher-blast-radius default, since this
# tool commits and merges on the shared store repo); --apply is required to write anything.
#
# Usage:
#   maintenance-run --tool project-links --intent <id> [--store <key>] [--plastic-home PATH] [--apply]
#   maintenance-run --tool rebuild-graph [--plastic-home PATH] [--apply]
#   maintenance-run --tool restore-intent-v1 <id> --at <ref> [--plastic-home PATH] [--apply] [--skip-links]
#
# project-links here is ALWAYS single-intent: --intent is required. A store-wide
# project-links sweep is the rare, owner-approved batch exception (D2) and is run directly
# with the plain `project-links` tool, never through this wrapper.
#
# --store <key> (a StoreDiscovery key, e.g. "global" or "project:dealintell") disambiguates
# a bare id that exists in more than one store (real, live examples: ids 26 and 15 both
# collide across stores today) - both project-links --intent and restore-intent-v1's own id
# resolution abort loud naming every candidate when ambiguous and --store is not given;
# never silently pick the first match.
#
# Exit codes: 0 applied or clean no-op; 1 usage error; 2 deferred (a target holds a fresh
# delivery lock); 3 the underlying tool reported failure; 4 precondition failed (the store
# working tree was not clean, or is not a git repo at all).

require "open3"
require "time"

require_relative "lib/store_discovery"
require_relative "lib/lock"
require_relative "lib/maintenance_git"

DEFAULT_HOME = File.join(Dir.home, ".plastic")

# Resolves `id` to exactly one directory. `store:` (a StoreDiscovery key) short-circuits
# resolution to that one store. Without it, more than one matching store is an ambiguity
# this method itself aborts on (never silently pick the first match - the same class of bug
# ACTION_1 fixes inside project-links itself; this helper guards every OTHER caller of
# resolve_dir_for_id, i.e. rebuild-graph's touched-id lock scan and restore-intent-v1's id
# resolution, both of which route through this one function).
def resolve_dir_for_id(discovery, id, store: nil)
  matches = []
  discovery[:stores].each do |s|
    next if store && s[:key] != store

    Dir.children(s[:store]).reject { |e| e.start_with?(".") }.each do |entry|
      full = File.join(s[:store], entry)
      next unless File.directory?(full)

      matches << [s[:key], full] if entry.split("--", 2).first == id.to_s
    end
  end

  return nil if matches.empty?
  if matches.length > 1
    abort_loud("intent #{id.inspect} is ambiguous across stores " \
               "(#{matches.map(&:first).join(", ")}); pass --store <key> to disambiguate")
  end
  matches.first.last
end

def abort_loud(msg, code = 1)
  warn "maintenance-run: #{msg}"
  exit code
end

def parse_argv(argv)
  opts = { tool: nil, intent: nil, store: nil, plastic_home: DEFAULT_HOME, apply: false,
           at: nil, skip_links: false, id: nil }
  i = 0
  while i < argv.length
    case argv[i]
    when "--tool" then opts[:tool] = argv[i += 1]
    when "--intent" then opts[:intent] = argv[i += 1]
    when "--store" then opts[:store] = argv[i += 1]
    when "--plastic-home" then opts[:plastic_home] = argv[i += 1]
    when "--apply" then opts[:apply] = true
    when "--at" then opts[:at] = argv[i += 1]
    when "--skip-links" then opts[:skip_links] = true
    else
      opts[:id] ||= argv[i] # positional id, restore-intent-v1 only
    end
    i += 1
  end
  opts
end

def check_not_fresh!(dir, id)
  return unless dir && Lock.fresh?(dir)

  abort_loud("deferred: intent #{id} holds a FRESH delivery lock; an active delivery is in " \
             "progress. Maintenance never acquires a lock and never waits on one; re-run " \
             "once the delivery finishes or the lock goes stale.", 2)
end

def stamp
  Time.now.utc.strftime("%Y%m%d%H%M%S")
end

def report_result(result)
  if result[:committed]
    puts "maintenance-run: applied and merged (#{result[:changed].size} path(s)): " \
         "#{result[:changed].join(", ")}"
  else
    puts "maintenance-run: no change (already canonical)."
  end
  exit 0
end

def run_project_links(home, intent, store, apply)
  abort_loud("--tool project-links requires --intent <id> (a store-wide sweep runs " \
             "scripts/project-links directly, never through maintenance-run)") unless intent

  discovery = StoreDiscovery.discover(home)
  dir = resolve_dir_for_id(discovery, intent, store: store) # aborts loud itself on ambiguity
  abort_loud("intent #{intent} not found under #{home}#{store ? " (--store #{store})" : ""}") unless dir
  check_not_fresh!(dir, intent)

  tool_path = File.expand_path("project-links", __dir__)
  base_args = ["--plastic-home", home, "--intent", intent]
  base_args += ["--store", store] if store

  unless apply
    system(RbConfig.ruby, tool_path, *base_args, "--dry-run")
    exit($?.exitstatus)
  end

  begin
    result = MaintenanceGit.run_scoped(
      repo_dir: home, branch_name: "maintenance/project-links-#{intent}-#{stamp}",
      commit_message: "chore: maintenance - project-links --intent #{intent}"
    ) do
      ok = system(RbConfig.ruby, tool_path, *base_args)
      raise "project-links failed for #{intent}" unless ok
    end
  rescue MaintenanceGit::DirtyWorkingTree, MaintenanceGit::NotAGitRepo => e
    abort_loud(e.message, 4)
  rescue RuntimeError => e
    abort_loud(e.message, 3)
  end
  report_result(result)
end

def run_rebuild_graph(home, apply)
  tool_path = File.expand_path("rebuild-graph", __dir__)
  load tool_path unless defined?(RebuildGraph) # matches test/*_test.rb's own load convention

  discovery = StoreDiscovery.discover(home)
  dry = RebuildGraph.new(plastic_home: home, dry_run: true)
  dry_results = dry.run
  touched_ids = dry_results.values.flat_map { |r| r[:changes].map { |c| c[:intent] } }.uniq

  touched_ids.each { |id| check_not_fresh!(resolve_dir_for_id(discovery, id), id) }

  unless apply
    puts "maintenance-run: DRY RUN, #{touched_ids.size} intent(s) would change: #{touched_ids.join(", ")}"
    exit 0
  end

  begin
    result = MaintenanceGit.run_scoped(
      repo_dir: home, branch_name: "maintenance/rebuild-graph-#{stamp}",
      commit_message: "chore: maintenance - rebuild-graph"
    ) do
      ok = system(RbConfig.ruby, tool_path, "--plastic-home", home)
      raise "rebuild-graph failed" unless ok
    end
  rescue MaintenanceGit::DirtyWorkingTree, MaintenanceGit::NotAGitRepo => e
    abort_loud(e.message, 4)
  rescue RuntimeError => e
    abort_loud(e.message, 3)
  end
  report_result(result)
end

def run_restore_intent_v1(home, id, at, store, apply, skip_links)
  abort_loud("restore-intent-v1 requires an intent id and --at <ref>") unless id && at

  discovery = StoreDiscovery.discover(home)
  # NOTE: restore-intent-v1's own CLI (scripts/restore-intent-v1:219-238, find_intent_dir)
  # already aborts loud on a cross-store id collision; this resolve_dir_for_id call is only
  # for the LOCK CHECK here (maintenance-run must know which one directory to check
  # Lock.fresh? against). --store is honored the same way for consistency; if omitted and
  # the id is ambiguous, this call aborts BEFORE restore-intent-v1 itself would have run.
  dir = resolve_dir_for_id(discovery, id, store: store)
  abort_loud("intent #{id} not found under #{home}#{store ? " (--store #{store})" : ""}") unless dir
  check_not_fresh!(dir, id)

  tool_path = File.expand_path("restore-intent-v1", __dir__)
  args = [tool_path, id, "--at", at, "--plastic-home", home]
  args << "--skip-links" if skip_links

  unless apply
    system(RbConfig.ruby, *args)
    exit($?.exitstatus)
  end

  begin
    result = MaintenanceGit.run_scoped(
      repo_dir: home, branch_name: "maintenance/restore-intent-v1-#{id}-#{stamp}",
      commit_message: "chore: maintenance - restore-intent-v1 #{id}"
    ) do
      ok = system(RbConfig.ruby, *args, "--apply")
      raise "restore-intent-v1 failed for #{id}" unless ok
    end
  rescue MaintenanceGit::DirtyWorkingTree, MaintenanceGit::NotAGitRepo => e
    abort_loud(e.message, 4)
  rescue RuntimeError => e
    abort_loud(e.message, 3)
  end
  report_result(result)
end

def main(argv)
  opts = parse_argv(argv)
  abort_loud("--tool is required (project-links|rebuild-graph|restore-intent-v1)") unless opts[:tool]

  case opts[:tool]
  when "project-links"
    run_project_links(opts[:plastic_home], opts[:intent], opts[:store], opts[:apply])
  when "rebuild-graph" then run_rebuild_graph(opts[:plastic_home], opts[:apply])
  when "restore-intent-v1"
    run_restore_intent_v1(opts[:plastic_home], opts[:id], opts[:at], opts[:store], opts[:apply], opts[:skip_links])
  else
    abort_loud("unknown --tool #{opts[:tool].inspect} " \
               "(expected project-links|rebuild-graph|restore-intent-v1)")
  end
end

main(ARGV) if $PROGRAM_NAME == __FILE__
```

## 9b. Tests - new file `test/maintenance_run_test.rb`

Build fixtures the same way `test/project_links_test.rb`/`test/rebuild_graph_test.rb` do
(`Dir.mktmpdir`, a `store/` plus `projects/<slug>/store/` layout), then `git init -b main` the
tmp home and commit the fixtures once (mirroring `test/end_intent_test.rb`'s
`Open3.capture3("git", "init", ...)` pattern) so `MaintenanceGit`'s clean-tree precheck passes.
Invoke the CLI via `Open3.capture3(RbConfig.ruby, MAINTENANCE_RUN, *args)` (subprocess, matching
`test/restore_intent_v1_test.rb`'s own `Open3.capture2(RbConfig.ruby, RESTORE, ...)` style).

```ruby
def test_defers_when_target_holds_a_fresh_delivery_lock
  # Write a delivery.lock with a fresh mtime in the target intent's directory
  # (JSON shape: {"type":"delivery","owner_session":"other-session", ...}; see
  # scripts/lib/lock.rb's `payload` for the exact keys, or just the minimal
  # {"owner_session":"x"} - Lock.fresh? only checks the file's mtime, not its content).
  lock_path = File.join(@home, "projects", "plastic", "store", "11--child", "delivery.lock")
  File.write(lock_path, '{"owner_session":"someone-else"}')

  out, status = Open3.capture3(RbConfig.ruby, MAINTENANCE_RUN, "--tool", "project-links",
                                "--intent", "11", "--plastic-home", @home, "--apply")
  assert_equal 2, status.exitstatus
  assert_match(/deferred/, out + out) # stdout/stderr both captured by capture3 separately; check err too
end

def test_applies_project_links_and_merges_when_clean
  out, status = Open3.capture3(RbConfig.ruby, MAINTENANCE_RUN, "--tool", "project-links",
                                "--intent", "11", "--plastic-home", @home, "--apply")
  assert_equal 0, status.exitstatus, out
  assert_match(/applied and merged/, out)

  log, = Open3.capture3("git", "-C", @home, "log", "--oneline")
  assert_match(/maintenance - project-links --intent 11/, log)
  status_out, = Open3.capture3("git", "-C", @home, "status", "--porcelain")
  assert_empty status_out.strip
  branches, = Open3.capture3("git", "-C", @home, "branch", "--list")
  refute_match(/maintenance\//, branches, "no maintenance branch should remain after merge")
end

def test_dry_run_makes_no_changes_by_default
  before = File.read(File.join(@home, "projects", "plastic", "store", "11--child", "11--child.md"))
  _out, status = Open3.capture3(RbConfig.ruby, MAINTENANCE_RUN, "--tool", "project-links",
                                 "--intent", "11", "--plastic-home", @home)
  assert_equal 0, status.exitstatus
  assert_equal before, File.read(File.join(@home, "projects", "plastic", "store", "11--child", "11--child.md"))
end

def test_project_links_without_intent_is_a_usage_error
  _out, status = Open3.capture3(RbConfig.ruby, MAINTENANCE_RUN, "--tool", "project-links",
                                 "--plastic-home", @home, "--apply")
  assert_equal 1, status.exitstatus
end

# FALSIFIABLE (208): an unrelated dirty file elsewhere in the store refuses the WHOLE run
# (exit 4), rather than being silently swept up or silently ignored.
def test_refuses_when_store_working_tree_is_dirty
  File.write(File.join(@home, "unrelated.md"), "dirty\n")
  _out, status = Open3.capture3(RbConfig.ruby, MAINTENANCE_RUN, "--tool", "project-links",
                                 "--intent", "11", "--plastic-home", @home, "--apply")
  assert_equal 4, status.exitstatus
end

def test_rebuild_graph_defers_when_any_touched_id_holds_a_fresh_lock
  # Reuse a fixture id known to change under rebuild-graph (adapt from
  # test/rebuild_graph_test.rb's own fixtures, e.g. an I1-backlink case); write a fresh
  # delivery.lock in THAT id's directory and confirm exit 2 with no branch created.
end

# FALSIFIABLE (208) and load-bearing for Task 13: real proof-case ids (26, 15) collide
# across stores. An ambiguous --intent with no --store must abort (exit 1, a usage-shaped
# failure, distinct from 2/3/4) rather than silently regenerate the WRONG store's intent.
def test_ambiguous_intent_across_stores_aborts_without_store_flag
  knowdb = File.join(@home, "projects", "knowdb", "store")
  FileUtils.mkdir_p(File.join(knowdb, "11--knowdb-collision"))
  File.write(File.join(knowdb, "11--knowdb-collision", "11--knowdb-collision.md"),
             "---\nid: \"11\"\nintent: t\nsources: []\nchain: []\ncreated: 2026-06-01\n" \
             "author: t\ntags: [t]\n---\n\n## Intent\nb\n")
  FileUtils.mkdir_p(File.join(@home, "projects", "knowdb"))
  File.write(File.join(@home, "projects", "knowdb", "INDEX.md"), "# Index\n\n## Completed\n")
  Open3.capture3("git", "-C", @home, "add", "-A")
  Open3.capture3("git", "-C", @home, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "add collision")

  _out, err, status = Open3.capture3(RbConfig.ruby, MAINTENANCE_RUN, "--tool", "project-links",
                                      "--intent", "11", "--plastic-home", @home, "--apply")
  assert_equal 1, status.exitstatus
  assert_match(/ambiguous/, err)
end

def test_store_flag_disambiguates_and_applies_to_the_named_store_only
  knowdb = File.join(@home, "projects", "knowdb", "store")
  FileUtils.mkdir_p(File.join(knowdb, "11--knowdb-collision"))
  File.write(File.join(knowdb, "11--knowdb-collision", "11--knowdb-collision.md"),
             "---\nid: \"11\"\nintent: t\nsources: []\nchain: []\ncreated: 2026-06-01\n" \
             "author: t\ntags: [t]\n---\n\n## Intent\nb\n")
  FileUtils.mkdir_p(File.join(@home, "projects", "knowdb"))
  File.write(File.join(@home, "projects", "knowdb", "INDEX.md"), "# Index\n\n## Completed\n")
  Open3.capture3("git", "-C", @home, "add", "-A")
  Open3.capture3("git", "-C", @home, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "add collision")

  before_knowdb = File.read(File.join(knowdb, "11--knowdb-collision", "11--knowdb-collision.md"))

  _out, _err, status = Open3.capture3(RbConfig.ruby, MAINTENANCE_RUN, "--tool", "project-links",
                                       "--intent", "11", "--store", "project:plastic",
                                       "--plastic-home", @home, "--apply")
  assert_equal 0, status.exitstatus

  assert_equal before_knowdb, File.read(File.join(knowdb, "11--knowdb-collision", "11--knowdb-collision.md")),
    "the --store-excluded knowdb intent 11 must be untouched"
end
```

Fill in `test_rebuild_graph_defers_when_any_touched_id_holds_a_fresh_lock` against this new
file's own `rebuild-graph`-flavored fixture (build one modeled on
`test/rebuild_graph_test.rb`'s `plastic:80 sources: ["22c"]` shape, ACTION_5); the pattern is
identical to the project-links defer test above, just pointed at the touched id's directory.

## Verify

`ruby -Itest test/maintenance_run_test.rb` green, then the full suite.
