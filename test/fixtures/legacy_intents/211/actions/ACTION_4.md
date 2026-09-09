# ACTION_4: Wire savepoint reconstruction into maintenance-run

Adds a fourth `--tool rebuild-savepoint` to `scripts/maintenance-run`, matching the exact shape
of the three existing tools (`run_project_links`, `run_rebuild_graph`, `run_restore_intent_v1`).
Composes two already-shipped `Bridge` primitives (`Bridge.rebuild_savepoint`,
`Bridge.append_terminal_savepoint`) with no new mechanical reconstruction code. Independent of
ACTION_1-3; can land in any order relative to them.

## 1. Requires (top of `scripts/maintenance-run`, alongside the existing three)
```ruby
require_relative "lib/bridge"
require_relative "lib/revisions_writer"
```
(`lib/store_discovery`, `lib/lock`, `lib/maintenance_git` are already required.)

## 2. New function, alongside `run_project_links`/`run_rebuild_graph`/`run_restore_intent_v1`

```ruby
def run_rebuild_savepoint(home, intent, store, apply)
  abort_loud("--tool rebuild-savepoint requires --intent <id>") unless intent

  discovery = StoreDiscovery.discover(home)
  dir = resolve_dir_for_id(discovery, intent, store: store)
  abort_loud("intent #{intent} not found under #{home}#{store ? " (--store #{store})" : ""}") unless dir
  check_not_fresh!(dir, intent)

  outcome_path = File.join(dir, "outcome.md")
  unless Bridge.stage_file_present?(outcome_path)
    abort_loud("intent #{intent}'s outcome.md is missing or a placeholder; the 124a recipe " \
               "requires a real disposition to echo, and 219 D6 forbids ever inventing one", 1)
  end

  frontmatter = File.read(outcome_path)[/\A---\n(.*?)\n---/m, 1].to_s
  disposition = frontmatter[/^disposition:\s*(\S+)/, 1]
  abort_loud("intent #{intent}'s outcome.md has no disposition: frontmatter field", 1) unless disposition

  unless apply
    puts "maintenance-run: DRY RUN, would reconstruct savepoint.md for #{intent} " \
         "(Bridge.rebuild_savepoint + Done #{disposition} echo)"
    exit 0
  end

  begin
    result = MaintenanceGit.run_scoped(
      repo_dir: home, branch_name: "maintenance/rebuild-savepoint-#{intent}-#{stamp}",
      commit_message: "chore: maintenance - rebuild-savepoint #{intent}"
    ) do
      Bridge.rebuild_savepoint(dir)
      Bridge.append_terminal_savepoint(dir, disposition)
      RevisionsWriter.append!(
        dir,
        why: "reconstruct missing operational savepoint.md (generic operational-gap predicate)",
        rule: "savepoint-operational-reconstruction",
        prior_location: "#{intent}/savepoint.md",
        change: "savepoint.md rebuilt from disk (Bridge.rebuild_savepoint) plus Done " \
                "#{disposition} echo appended (Bridge.append_terminal_savepoint); disposition " \
                "read from outcome.md's own frontmatter, never invented"
      )
    end
  rescue MaintenanceGit::DirtyWorkingTree, MaintenanceGit::NotAGitRepo => e
    abort_loud(e.message, 4)
  rescue RuntimeError => e
    abort_loud(e.message, 3)
  end
  report_result(result)
end
```

## 3. Wire into `main`'s case statement and the usage strings
```ruby
def main(argv)
  opts = parse_argv(argv)
  abort_loud("--tool is required (project-links|rebuild-graph|restore-intent-v1|rebuild-savepoint)") unless opts[:tool]

  case opts[:tool]
  when "project-links"
    run_project_links(opts[:plastic_home], opts[:intent], opts[:store], opts[:apply])
  when "rebuild-graph" then run_rebuild_graph(opts[:plastic_home], opts[:apply])
  when "restore-intent-v1"
    run_restore_intent_v1(opts[:plastic_home], opts[:id], opts[:at], opts[:store], opts[:apply], opts[:skip_links])
  when "rebuild-savepoint"
    run_rebuild_savepoint(opts[:plastic_home], opts[:intent], opts[:store], opts[:apply])
  else
    abort_loud("unknown --tool #{opts[:tool].inspect} " \
               "(expected project-links|rebuild-graph|restore-intent-v1|rebuild-savepoint)")
  end
end
```
Update the file's header `Usage:` comment block to add:
```
#   maintenance-run --tool rebuild-savepoint --intent <id> [--store <key>] [--plastic-home PATH] [--apply]
```

## 4. Do NOT invoke this tool against the owner's 44 gaps in this action
Wiring only. Running it in batch is an explicit, separately owner-approved future action (D8) -
no `--apply` run against any real store id happens as part of this intent's Exec.

## Verification for this action
- A hermetic fixture (tmp `--plastic-home`, one terminal intent dir with a real `outcome.md`
  carrying `disposition: delivered` and a `savepoint.md` missing the Done line): dry-run prints
  the intended reconstruction and exits 0 with no file changes; `--apply` reconstructs
  `savepoint.md` (via the two `Bridge` calls) and appends exactly one `revisions.md` entry via
  `RevisionsWriter`, inside one `MaintenanceGit.run_scoped` commit.
- A second fixture with a missing/placeholder `outcome.md`: the tool aborts loud (exit 1) before
  touching `MaintenanceGit` at all, in both dry-run and `--apply` modes.
- A fixture whose target dir holds a fresh `delivery.lock`: `check_not_fresh!` defers (exit 2),
  matching the other three tools' behavior exactly.
