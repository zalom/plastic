# ACTION_3: clear RUBYOPT in the four ruby-side spawner scripts

Intent: 235, Make the first install work on a clean Mac.
Satisfies: G2. Preserves AC10.

## Context you need (do not go looking for it)

Four Ruby scripts spawn a ruby child process. None clears `RUBYOPT`, so an exported
`RUBYOPT=--yjit` reaches the child and kills it on an old interpreter.

The mechanism matters and is easy to get wrong. A Hash passed as the FIRST argument to `system`,
`Open3.capture3`, `IO.popen` or `Process.spawn` MERGES onto the inherited environment. It clears
nothing unless the key is present with a `nil` or empty-string value. So the fix is to add
`{"RUBYOPT" => nil}` as the leading argument, not to pass an empty hash and not to delete a key
somewhere else.

Verified behavior, from the research: with `RUBYOPT=--yjit` set in the parent,
`Open3.capture3({"RUBYOPT" => nil}, "/usr/bin/ruby", "-v")` succeeds, while
`Open3.capture3("/usr/bin/ruby", "-v")` crashes.

One site is a backtick command, which goes through a shell, so a hash is not available there. It
uses the same bash form the hook launchers use: `env -u RUBYOPT ruby`.

Passing an env hash as the first argument does NOT change `system`'s return value or `$?`, so
existing `exit($?.exitstatus)` and `unless ok` logic keeps working unchanged.

## Where you work

Worktree root:
`/Users/zlatko/apps/personal/plastic/.claude/worktrees/235--install-on-a-clean-mac`

If Edit or Write is denied or writes to the wrong tree, fall back to a Bash ruby write using the
absolute path and ` # plastic-ok` appended, with `String#sub` in BLOCK form.

## The four files and nine edits

Line numbers below were verified against the current files today. Match on the text.

### 1. `scripts/link-suggest`, line 198, one backtick spawn

BEFORE:
```ruby
    out = `ruby #{File.join(Dir.home, ".plastic", "scripts", "qmd-sync")} search #{shell_quote(query)} 2>/dev/null`
```
AFTER:
```ruby
    out = `env -u RUBYOPT ruby #{File.join(Dir.home, ".plastic", "scripts", "qmd-sync")} search #{shell_quote(query)} 2>/dev/null`
```

Backticks run through a shell, so the bash clearing form applies. `env -u RUBYOPT` removes the
variable for the child. Nothing else on the line changes: the interpolation, the quoting helper
and the `2>/dev/null` all stay exactly as they are.

### 2. `scripts/maintenance-run`, five `system` spawns (lines 133, 142, 174, 203, 212)

Line 133, BEFORE:
```ruby
    system(RbConfig.ruby, tool_path, *base_args, "--dry-run")
```
AFTER:
```ruby
    system({"RUBYOPT" => nil}, RbConfig.ruby, tool_path, *base_args, "--dry-run")
```

Line 142, BEFORE:
```ruby
      ok = system(RbConfig.ruby, tool_path, *base_args)
```
AFTER:
```ruby
      ok = system({"RUBYOPT" => nil}, RbConfig.ruby, tool_path, *base_args)
```

Line 174, BEFORE:
```ruby
      ok = system(RbConfig.ruby, tool_path, "--plastic-home", home)
```
AFTER:
```ruby
      ok = system({"RUBYOPT" => nil}, RbConfig.ruby, tool_path, "--plastic-home", home)
```

Line 203, BEFORE:
```ruby
    system(RbConfig.ruby, *args)
```
AFTER:
```ruby
    system({"RUBYOPT" => nil}, RbConfig.ruby, *args)
```

Line 212, BEFORE:
```ruby
      ok = system(RbConfig.ruby, *args, "--apply")
```
AFTER:
```ruby
      ok = system({"RUBYOPT" => nil}, RbConfig.ruby, *args, "--apply")
```

Keep the existing indentation on every line. Lines 142, 174 and 212 sit inside a
`MaintenanceGit.run_scoped` block and are indented six spaces. Lines 133 and 203 are indented
four.

Do not touch any other `system(...)` call in this file. Only the five above spawn ruby.

### 3. `scripts/restore-intent-v1`, line 274, one `system` spawn

BEFORE:
```ruby
    system(RbConfig.ruby, project_links, "--plastic-home", plastic_home)
```
AFTER:
```ruby
    system({"RUBYOPT" => nil}, RbConfig.ruby, project_links, "--plastic-home", plastic_home)
```

The `return if $?.success?` on the next line still works. The env hash does not change `$?`.

### 4. `scripts/hook-continue`, lines 18 and 39, two `Open3.capture3` spawns

Line 18, BEFORE:
```ruby
cockpit, _err, status = Open3.capture3("ruby", dashboard, "continue")
```
AFTER:
```ruby
cockpit, _err, status = Open3.capture3({"RUBYOPT" => nil}, "ruby", dashboard, "continue")
```

Line 39, BEFORE:
```ruby
  data_json, _data_err, data_status = Open3.capture3("ruby", dashboard, "continue", "--data")
```
AFTER:
```ruby
  data_json, _data_err, data_status = Open3.capture3({"RUBYOPT" => nil}, "ruby", dashboard, "continue", "--data")
```

## Hard rules

- Use `{"RUBYOPT" => nil}` everywhere in Ruby. Do not mix in `""` at some sites, the AC4 test in
  ACTION_6 accepts both but the codebase should read one way.
- The env hash goes FIRST, before the command. Anywhere else it is just an argument.
- No added line may contain an em-dash or an en-dash.
- Do NOT edit `scripts/codex-hook` or `scripts/hook-session-start`. Both are off limits. Both
  still carry uncleared ruby spawns, which is a recorded, deliberate handoff to the codex-fixes
  roadmap (spec.md, D5). If you think one needs an edit, stop and report instead.
- Do NOT edit `scripts/lib/bridge.rb`, `scripts/lib/lock.rb` or `scripts/lib/worktree.rb`.
  `worktree.rb` spawns only `git`, so it has no exposure at all.

## Verify

1. Every file still parses:

```
cd /Users/zlatko/apps/personal/plastic/.claude/worktrees/235--install-on-a-clean-mac
for f in scripts/link-suggest scripts/maintenance-run scripts/restore-intent-v1 scripts/hook-continue; do ruby -c "$f"; done
```

Four `Syntax OK` lines.

2. The nine sites are cleared and none is left behind:

```
ruby -e 'files=%w[scripts/link-suggest scripts/maintenance-run scripts/restore-intent-v1 scripts/hook-continue]; calls=["system(","Open3.capture3(","IO.popen(","Process.spawn("]; bad=files.flat_map { |p| File.readlines(p).each_with_index.map { |l,i| next nil if l.strip.start_with?("#"); t=l.count("`"); spawn = (calls.any? { |c| l.include?(c) } && (l.include?("RbConfig.ruby") || l.include?(%q{"ruby"}))) || (t>=2 && t.even? && l =~ /`\s*(env -u RUBYOPT\s+)?ruby\s/); next nil unless spawn; (l.include?(%q{"RUBYOPT" =>}) || l.include?("env -u RUBYOPT ruby")) ? nil : "#{p}:#{i+1}: #{l.strip}" }.compact }; puts bad.empty? ? "OK: every ruby spawn in the four scripts clears RUBYOPT" : bad'
```

Must print the OK line. Before your edits this same command reports exactly 9 offenders
(link-suggest 1, maintenance-run 5, restore-intent-v1 1, hook-continue 2). If you see a
different set, stop and report.

The balanced-backtick condition (`t>=2 && t.even?`) matters: `scripts/restore-intent-v1:207` is a
warning STRING holding a single unmatched backtick followed by the word ruby, closed two lines
later. It is prose, not a spawn site. Do not "fix" it.

3. Count check, nine cleared sites total:

```
grep -c 'RUBYOPT' scripts/link-suggest scripts/maintenance-run scripts/restore-intent-v1 scripts/hook-continue
```

Expected: link-suggest 1, maintenance-run 5, restore-intent-v1 1, hook-continue 2. Total 9.

4. The full suite is green:

```
ruby -Itest -e 'Dir["test/*_test.rb"].each { |f| require File.expand_path(f) }'
```

There is no `Rakefile`, so `rake test` does not exist. Pay attention to
`test/maintenance_run_test.rb` and any restore-intent or link-suggest tests: if one of them
asserts an exact `system` argument list, it needs the leading hash added to its expectation. If a
test fails only because of the new first argument, update the test expectation, not the fix.

5. Off-limits files untouched:

```
git -C /Users/zlatko/apps/personal/plastic/.claude/worktrees/235--install-on-a-clean-mac diff --name-only | grep -E 'codex-hook|hook-session-start|lib/(bridge|lock|worktree)\.rb'
```

Must print nothing.

## Done when

All nine ruby-side spawn sites clear `RUBYOPT`, the scan in step 2 prints OK, the suite is green,
and no off-limits file appears in the diff.
