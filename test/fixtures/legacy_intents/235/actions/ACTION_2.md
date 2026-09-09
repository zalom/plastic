# ACTION_2: clear RUBYOPT in the nine bash hook launchers

Intent: 235, Make the first install work on a clean Mac.
Satisfies: G2, G4. Preserves AC9, AC10.

## Context you need (do not go looking for it)

Every hook launcher under `hooks/` is a `/bin/bash` script that spawns `ruby`. None of them
clears `RUBYOPT` today, so a shell that exports `RUBYOPT=--yjit` hands `--yjit` to a child ruby.
On a clean Mac that child is `/usr/bin/ruby` 2.6.10, which does not know the flag and dies.

The fix at every site is the same: put `env -u RUBYOPT` immediately in front of `ruby`. BSD
`env` on macOS supports `-u NAME` (verified on this machine). `env -u` REMOVES the variable,
which is what we need. Do not use `RUBYOPT= ruby` here, the whole codebase should read the same.

One of these edits carries extra weight. `hooks/session-start:9` is how `scripts/hook-session-start`
gets launched, and that script is OFF LIMITS to this intent even though it has two uncleared
backtick spawns of its own. Clearing `RUBYOPT` in the launcher removes the variable from that
ruby process's environment, so both of its child spawns inherit an already-clean environment.
That is goal G4, fixed transitively with zero changed lines in the off-limits file.

## Where you work

Worktree root:
`/Users/zlatko/apps/personal/plastic/.claude/worktrees/235--install-on-a-clean-mac`

All nine files are under `<worktree>/hooks/`. If Edit or Write is denied or writes to the wrong
tree, fall back to a Bash ruby write using the absolute path and ` # plastic-ok` appended to the
command, with `String#sub` in BLOCK form.

## The nine files and fourteen edits

Line numbers are locators only. MATCH ON THE TEXT. The research table this came from has stale
line numbers for four of these files; the text below was read from the current files today.

### 1. `hooks/auto-arm` (2 sites, lines 3 and 5)

BEFORE:
```bash
MESSAGE=$(echo "$INPUT" | ruby -rjson -e 'puts JSON.parse(STDIN.read)["user_prompt"].to_s' 2>/dev/null || echo "")
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ruby "$SCRIPT_DIR/../scripts/hook-auto-arm" "$MESSAGE"
```
AFTER:
```bash
MESSAGE=$(echo "$INPUT" | env -u RUBYOPT ruby -rjson -e 'puts JSON.parse(STDIN.read)["user_prompt"].to_s' 2>/dev/null || echo "")
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
env -u RUBYOPT ruby "$SCRIPT_DIR/../scripts/hook-auto-arm" "$MESSAGE"
```

### 2. `hooks/bash-gate` (1 site, line 3)

BEFORE:
```bash
exec ruby "$SCRIPT_DIR/../scripts/hook-bash-gate"
```
AFTER:
```bash
exec env -u RUBYOPT ruby "$SCRIPT_DIR/../scripts/hook-bash-gate"
```

`exec env ...` is correct: `env` replaces the shell, then `ruby` replaces `env`. The process
count is unchanged.

### 3. `hooks/check-update` (1 site, line 34, research said 31)

BEFORE:
```bash
  TARGET=$(printf '%s' "$TAGS" | ruby "$SELECTOR" "$CURRENT" 2>/dev/null)
```
AFTER:
```bash
  TARGET=$(printf '%s' "$TAGS" | env -u RUBYOPT ruby "$SELECTOR" "$CURRENT" 2>/dev/null)
```

Keep the two-space indent. This line lives inside a backgrounded subshell.

### 4. `hooks/continue` (2 sites, lines 3 and 17, research said 4 and 19)

BEFORE (line 3):
```bash
MESSAGE=$(echo "$INPUT" | ruby -rjson -e 'puts JSON.parse(STDIN.read)["user_prompt"]' 2>/dev/null || echo "")
```
AFTER:
```bash
MESSAGE=$(echo "$INPUT" | env -u RUBYOPT ruby -rjson -e 'puts JSON.parse(STDIN.read)["user_prompt"]' 2>/dev/null || echo "")
```

BEFORE (line 17):
```bash
  OUTPUT=$(ruby "$SCRIPT_DIR/../scripts/hook-continue" "$INDEX" "$STORE_ROOT" "$MODE" 2>/dev/null)
```
AFTER:
```bash
  OUTPUT=$(env -u RUBYOPT ruby "$SCRIPT_DIR/../scripts/hook-continue" "$INDEX" "$STORE_ROOT" "$MODE" 2>/dev/null)
```

Note: this file already contains a `cat <<'HOOKJSON'` heredoc at lines 22 to 29. Leave it alone.
It is a plain heredoc, not a heredoc inside `$(...)`, so it is bash 3.2 safe.

### 5. `hooks/edit-gates` (1 site, line 3)

BEFORE:
```bash
exec ruby "$SCRIPT_DIR/../scripts/hook-edit-gates"
```
AFTER:
```bash
exec env -u RUBYOPT ruby "$SCRIPT_DIR/../scripts/hook-edit-gates"
```

### 6. `hooks/future-intent-check` (2 sites, lines 3 and 25, research said 3 and 23)

BEFORE (line 3):
```bash
MESSAGE=$(echo "$INPUT" | ruby -rjson -e 'puts JSON.parse(STDIN.read)["user_prompt"].downcase' 2>/dev/null || echo "")
```
AFTER:
```bash
MESSAGE=$(echo "$INPUT" | env -u RUBYOPT ruby -rjson -e 'puts JSON.parse(STDIN.read)["user_prompt"].downcase' 2>/dev/null || echo "")
```

BEFORE (line 25, the last line of the file):
```bash
ruby "$SCRIPT_DIR/../scripts/hook-future-intent-check" "$STORE_ROOT" "$MESSAGE"
```
AFTER:
```bash
env -u RUBYOPT ruby "$SCRIPT_DIR/../scripts/hook-future-intent-check" "$STORE_ROOT" "$MESSAGE"
```

### 7. `hooks/gate-check` (3 sites, lines 3, 9 and 12, research said 4, 10 and 15)

BEFORE (line 3):
```bash
FILE_PATH=$(echo "$INPUT" | ruby -rjson -e 'data = JSON.parse(STDIN.read); puts data.dig("tool_params", "file_path") || data.dig("tool_input", "file_path") || ""' 2>/dev/null)
```
AFTER:
```bash
FILE_PATH=$(echo "$INPUT" | env -u RUBYOPT ruby -rjson -e 'data = JSON.parse(STDIN.read); puts data.dig("tool_params", "file_path") || data.dig("tool_input", "file_path") || ""' 2>/dev/null)
```

BEFORE (line 9):
```bash
SESSION_ID=$(echo "$INPUT" | ruby -rjson -e 'data = JSON.parse(STDIN.read); puts data.dig("session_id") || ""' 2>/dev/null)
```
AFTER:
```bash
SESSION_ID=$(echo "$INPUT" | env -u RUBYOPT ruby -rjson -e 'data = JSON.parse(STDIN.read); puts data.dig("session_id") || ""' 2>/dev/null)
```

BEFORE (line 12, the last line of the file):
```bash
ruby "$SCRIPT_DIR/../scripts/hook-gate-check" "$FILE_PATH" "$SESSION_ID"
```
AFTER:
```bash
env -u RUBYOPT ruby "$SCRIPT_DIR/../scripts/hook-gate-check" "$FILE_PATH" "$SESSION_ID"
```

### 8. `hooks/power-tools` (1 site, line 8, the last line of the file)

BEFORE:
```bash
exec ruby "$SCRIPT_DIR/../scripts/hook-power-tools"
```
AFTER:
```bash
exec env -u RUBYOPT ruby "$SCRIPT_DIR/../scripts/hook-power-tools"
```

### 9. `hooks/session-start` (1 site, line 9, the last line of the file). This is the G4 edit.

BEFORE:
```bash
ruby "$SCRIPT_DIR/../scripts/hook-session-start" "$GLOBAL_INDEX" "$HOME/.plastic" "global" "${CLAUDE_PLUGIN_ROOT:-}"
```
AFTER:
```bash
env -u RUBYOPT ruby "$SCRIPT_DIR/../scripts/hook-session-start" "$GLOBAL_INDEX" "$HOME/.plastic" "global" "${CLAUDE_PLUGIN_ROOT:-}"
```

## Files in hooks/ you must NOT change

- `hooks/hooks.json`: a JSON registry, not a script.
- `hooks/run-hook`: `exec`s a sibling hook by path and lets that file's shebang choose the
  interpreter. It never types `ruby`, so it is not a spawn site.
- `hooks/savepoint`: pure bash, prints one JSON heredoc. No ruby.
- `hooks/statusline`: pure bash by design, its own header says "No ruby, no jq". No ruby.

Do not add `env -u RUBYOPT` anywhere in these four. There is nothing to clear.

## Hard rules

- macOS `/bin/bash` 3.2 only. Do not introduce a heredoc inside `$(...)`, an associative array,
  `${var^^}`, or any bash 4 feature. These edits add none of that.
- No added line may contain an em-dash or an en-dash.
- Do NOT edit `scripts/hook-session-start`. It is off limits, and it gets fixed transitively by
  edit 9 above. If you believe it needs an edit, stop and report instead.

## Verify

1. Every file still parses as bash:

```
cd /Users/zlatko/apps/personal/plastic/.claude/worktrees/235--install-on-a-clean-mac
for f in hooks/auto-arm hooks/bash-gate hooks/check-update hooks/continue hooks/edit-gates hooks/future-intent-check hooks/gate-check hooks/power-tools hooks/session-start; do /bin/bash -n "$f" && echo "ok $f"; done
```

All nine must print `ok`.

2. Fourteen clearing sites are present:

```
grep -c 'env -u RUBYOPT ruby' hooks/auto-arm hooks/bash-gate hooks/check-update hooks/continue hooks/edit-gates hooks/future-intent-check hooks/gate-check hooks/power-tools hooks/session-start
```

Expected counts: auto-arm 2, bash-gate 1, check-update 1, continue 2, edit-gates 1,
future-intent-check 2, gate-check 3, power-tools 1, session-start 1. Total 14.

Before your edits the scan in step 3 below reports exactly these same 14 lines as offenders.
That was verified against the current sources, so if you see a different set, stop and report.

3. No uncleared `ruby` token is left anywhere in `hooks/`:

```
ruby -e 'bad=Dir["hooks/*"].select { |p| File.file?(p) && !p.end_with?(".json") }.flat_map { |p| File.readlines(p).each_with_index.map { |l,i| (l.strip.start_with?("#") ? nil : (l.gsub("env -u RUBYOPT ruby ", "CLEARED ") =~ /(?<![\w.\/-])ruby(?=\s)/ ? "#{p}:#{i+1}: #{l.strip}" : nil)) }.compact }; puts bad.empty? ? "OK: every ruby spawn in hooks/ clears RUBYOPT" : bad'
```

Must print the OK line.

4. The full suite is still green:

```
ruby -Itest -e 'Dir["test/*_test.rb"].each { |f| require File.expand_path(f) }'
```

There is no `Rakefile` in this repo, so `rake test` does not exist. Use the loader command above.
Never `ruby -Itest test/*_test.rb`, which silently runs only the first file.

5. `scripts/hook-session-start` has zero changed lines:

```
git -C /Users/zlatko/apps/personal/plastic/.claude/worktrees/235--install-on-a-clean-mac diff --name-only -- scripts/hook-session-start
```

Must print nothing.

## Done when

All nine launchers clear `RUBYOPT`, `bash -n` passes on each, the scan in step 3 prints OK, the
suite is green, and the off-limits file is untouched.
