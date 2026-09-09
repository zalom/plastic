# ACTION_2: Delete the amnesty file and every reader

Removes the shipped store-specific id list outright. Depends on ACTION_1 landing first (or in
the same commit) so `doctor.rb` never briefly references a predicate that still expects
`@bookend_amnesty` to exist.

## 1. Delete the file
- Delete `scripts/lib/legacy_bookend_amnesty.rb` entirely.

## 2. `scripts/doctor.rb` - remove every reference
- Delete line 29: `require_relative "lib/legacy_bookend_amnesty"`.
- Delete lines 53-56 (the comment block plus):
  ```ruby
  # Single source of truth for the pre-161 legacy Done-bookend amnesty list
  # lives in LegacyBookendAmnesty (intent 170a). Alias it here so the two can
  # never drift.
  LEGACY_BOOKEND_AMNESTY = LegacyBookendAmnesty::LIST
  ```
- Change the constructor (line 97-103) from:
  ```ruby
  def initialize(plastic_home: DEFAULT_PLASTIC_HOME, agents: DEFAULT_AGENTS,
                  bookend_amnesty: LEGACY_BOOKEND_AMNESTY, runner: Doctor.default_runner)
    @plastic_home = plastic_home
    @agents = agents
    @bookend_amnesty = bookend_amnesty
    @runner = runner
  end
  ```
  to:
  ```ruby
  def initialize(plastic_home: DEFAULT_PLASTIC_HOME, agents: DEFAULT_AGENTS,
                  runner: Doctor.default_runner)
    @plastic_home = plastic_home
    @agents = agents
    @runner = runner
  end
  ```
  No `bookend_amnesty:` keyword survives anywhere on `Doctor.new`; a caller that still passes it
  now raises `ArgumentError: unknown keyword`, which is the intended forcing function for
  ACTION_5's test rewrites.

## 3. `scripts/lib/installer_core.rb` - remove the manifest registration
- Delete the `core_files` hash entry at line 361:
  ```ruby
  "scripts/lib/legacy_bookend_amnesty.rb" => "scripts/lib/legacy_bookend_amnesty.rb",
  ```
- No other edit needed in this file: `install_agent`'s existing `old_files - new_files` diff
  (`installer_core.rb:511-512`) already prunes any file removed from `core_files` on the next
  install/update, deleting the stale installed copy under `~/.plastic/scripts/lib/` with no new
  migration code. Do not add a separate one-shot migration for this file.

## Verification for this action
- `grep -rn "bookend_amnesty\|LegacyBookendAmnesty" scripts/ test/` returns zero matches once
  ACTION_5's test rewrites also land (this action alone still leaves the 5 test call sites in
  `test/doctor_done_signals_test.rb` referencing the now-deleted keyword, which is exactly the
  forcing function ACTION_5 resolves).
- `ruby -c scripts/doctor.rb` and `ruby -c scripts/lib/installer_core.rb` both parse clean.
- `npm pack --dry-run 2>&1 | grep legacy_bookend_amnesty` returns nothing (the file no longer
  exists to be packed).
