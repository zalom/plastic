# ACTION_5: add the doctor check that reports the resolved ruby against the floor

Intent: 235, Make the first install work on a clean Mac.
Satisfies: AC8, AC12.
Depends on: ACTION_4 (this check calls `RubyProbe.resolve` as its default probe).

## Context you need (do not go looking for it)

Even after a user installs Ruby 3.3 with mise, a hook launched by the agent application can still
resolve bare `ruby` to `/usr/bin/ruby` 2.6, because mise activation happens on shell prompt
render and never reaches a non-interactive spawned process. Doctor is Plastic's maintenance front
door, so it reports this. Exactly one new check. It reports, it never repairs and it never pins
an interpreter path.

`scripts/doctor.rb` builds every finding through one helper (line 216):

```ruby
def check(category:, name:, status:, message:, details: [], fixable: false, fix_hint: nil)
```

Status is one of `"pass"`, `"warn"`, `"fail"`. The closest existing check in shape is
`codex_version_floor_check` (line 1927): probe a version through an injected seam, compare it
against a constant, and emit an honest branch for each outcome including "could not determine".
The closest existing check in injection style is `check_serena(cwd:, path_probe:
PowerTools.method(:which_serena))` (line 2829): a keyword argument with a real default.

## Where you work

Worktree root:
`/Users/zlatko/apps/personal/plastic/.claude/worktrees/235--install-on-a-clean-mac`

If Edit or Write is denied or writes to the wrong tree, fall back to a Bash ruby write using
absolute paths and ` # plastic-ok` appended.

## Step 1: two new requires in `scripts/doctor.rb`

Find the require block at lines 19 to 32.

BEFORE (the last line of the block):
```ruby
require_relative "lib/power_tools"
```
AFTER:
```ruby
require_relative "lib/power_tools"
require_relative "lib/preflight"
require_relative "lib/ruby_probe"
```

`Preflight::RUBY_FLOOR` and `Preflight::RUBY_PIN` are the single source of truth for the floor and
the pinned version. Do NOT retype `"3.0.0"` or `"3.3"` as a literal anywhere in doctor.

Both files are in the installer core-file map, `preflight.rb` already and `ruby_probe.rb` from
ACTION_4, so the installed `doctor.rb` will find both.

## Step 2: the check method

Insert it in `scripts/doctor.rb` immediately AFTER the end of `check_enola` (which ends around
line 2859) and BEFORE the `# --- Check category: skill-lint` comment block at line 2861.

```ruby
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
```

`safe_version` already exists on `Doctor` at line 1968. Reuse it, do not add another.

## Step 3: register the check so it actually runs

In `Doctor#run_checks` (around line 2905).

BEFORE:
```ruby
    all_checks += check_qmd
    all_checks += check_done_signals(scopes: ["global"])
```
AFTER:
```ruby
    all_checks += check_qmd
    all_checks += check_ruby_runtime
    all_checks += check_done_signals(scopes: ["global"])
```

Register it ONLY there. Specifically:

- NOT in `run_core_checks`. That scope is binary, so any warn becomes a hard fail. A machine
  whose PATH ruby is old can still have a perfectly correct install, and turning that into a
  `--core` failure would break install verification over a risk this check can only report.
- NOT in `run_store_checks` or `run_intent_check`. Neither is about the runtime.

## Step 4: docs sync

AGENTS.md requires docs to move with the framework. Open
`/Users/zlatko/apps/personal/plastic/.claude/worktrees/235--install-on-a-clean-mac/docs/internals.md`
and find the full-run bullet at line 367.

BEFORE:
```
- **Full run (no flag)**: three-state. Walks every check category (global store,
  conventions across all intents, agent registration, core files, project stores,
  deprecations). This is what `/plastic-doctor` invokes. It also runs automatically
  after every `plastic-update` (informational: prints the report but does not block
  or revert the update).
```
AFTER:
```
- **Full run (no flag)**: three-state. Walks every check category (global store,
  conventions across all intents, agent registration, core files, project stores,
  deprecations, runtime). This is what `/plastic-doctor` invokes. It also runs automatically
  after every `plastic-update` (informational: prints the report but does not block
  or revert the update).

The `runtime` category holds one check, `ruby_floor`: it spawns bare `ruby` the way a hook
launcher does, asks the resolved interpreter for its own version and absolute path, and warns
when that is below `Preflight::RUBY_FLOOR`. It exists because a version manager that activates
on shell prompt render does not reach a hook process spawned by the agent application, so the
ruby your shell has is not always the ruby your hooks get. The check reports only. It never
pins an interpreter and never repairs.
```

No em-dash, no en-dash in the added lines. `docs/` is user-facing, so keep the wording plain.

## Step 5: create `test/doctor_ruby_runtime_test.rb`

New file at
`/Users/zlatko/apps/personal/plastic/.claude/worktrees/235--install-on-a-clean-mac/test/doctor_ruby_runtime_test.rb`:

```ruby
# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"

require_relative "../scripts/doctor"

# Hermetic tests for doctor's runtime/ruby_floor check (intent 235, D6, AC8). The
# ruby-resolution probe is injected as a keyword lambda, so no test spawns a process,
# reads ENV or writes ENV. No eval.
class DoctorRubyRuntimeTest < Minitest::Test
  # Escape sequences, not the literal characters. A literal here would itself be an added
  # line carrying an em-dash, which is exactly what AC10 forbids.
  EM_DASH = "\u2014"
  EN_DASH = "\u2013"

  def setup
    @home = Dir.mktmpdir("plastic-doctor-runtime")
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  def doctor
    Doctor.new(plastic_home: @home)
  end

  def probe_for(version, path = "/usr/bin/ruby")
    ->(*) { { found: true, version: version, path: path } }
  end

  def absent_probe
    ->(*) { { found: false, version: nil, path: nil } }
  end

  def only_check(checks)
    assert_equal 1, checks.size, "the runtime category must hold exactly one check"
    checks.first
  end

  def test_below_floor_warns_and_names_the_version_the_path_and_the_floor
    result = only_check(doctor.check_ruby_runtime(probe: probe_for("2.6.10")))

    assert_equal "runtime", result[:category]
    assert_equal "ruby_floor", result[:name]
    assert_equal "warn", result[:status]
    assert_includes result[:message], "2.6.10"
    assert_includes result[:message], "/usr/bin/ruby"
    assert_includes result[:message], Preflight::RUBY_FLOOR
    assert_includes result[:fix_hint], "ruby@#{Preflight::RUBY_PIN}"
  end

  def test_at_the_floor_passes
    result = only_check(doctor.check_ruby_runtime(probe: probe_for("3.0.0")))

    assert_equal "pass", result[:status]
    assert_includes result[:message], "3.0.0"
  end

  def test_above_the_floor_passes
    result = only_check(doctor.check_ruby_runtime(probe: probe_for("3.3.5", "/opt/rubies/3.3.5/bin/ruby")))

    assert_equal "pass", result[:status]
    assert_includes result[:message], "3.3.5"
    assert_includes result[:message], "/opt/rubies/3.3.5/bin/ruby"
  end

  def test_no_resolvable_ruby_warns_instead_of_crashing
    result = only_check(doctor.check_ruby_runtime(probe: absent_probe))

    assert_equal "warn", result[:status]
    assert_includes result[:message], "Could not determine"
  end

  def test_an_unparseable_version_warns_instead_of_crashing
    result = only_check(doctor.check_ruby_runtime(probe: probe_for("banana")))

    assert_equal "warn", result[:status]
    assert_includes result[:message], "Could not determine"
  end

  def test_the_check_never_repairs
    [probe_for("2.6.10"), probe_for("3.3.5"), absent_probe].each do |probe|
      result = only_check(doctor.check_ruby_runtime(probe: probe))

      refute result[:fixable], "runtime/ruby_floor reports only, it must never be fixable"
      refute_equal "fail", result[:status], "runtime/ruby_floor must never fail the run"
    end
  end

  def test_no_message_contains_an_em_or_en_dash
    [probe_for("2.6.10"), probe_for("3.3.5"), absent_probe].each do |probe|
      result = only_check(doctor.check_ruby_runtime(probe: probe))

      refute_includes result[:message], EM_DASH
      refute_includes result[:message], EN_DASH
    end
  end

  # Guard: a check that exists but is never called reports nothing. Source scan rather
  # than a live doctor run, so the test stays hermetic and fast.
  def test_the_check_is_registered_in_the_full_run_and_not_in_the_binary_core_run
    source = File.read(File.expand_path("../scripts/doctor.rb", __dir__))
    full_run = source[/def run_checks\(agent_key\).*?\n  end/m]
    core_run = source[/def run_core_checks\(agent_key\).*?\n  end/m]

    assert_includes full_run, "check_ruby_runtime"
    refute_includes core_run, "check_ruby_runtime",
      "the binary --core scope turns any warn into a fail, so this report-only check stays out of it"
  end
end
```

## Hard rules

- Status for below-floor stays `"warn"`. Do not upgrade it to `"fail"`. Report only, spec.md D6.
- No `eval`, no `ENV` seam, no global config seam, no network. The probe is always injected in
  tests.
- Do not add a second check. Exactly one, per spec.md D6.
- Do not duplicate the floor value. Read `Preflight::RUBY_FLOOR`.
- No added line, in code or in docs, may contain an em-dash or an en-dash.

## Verify

```
cd /Users/zlatko/apps/personal/plastic/.claude/worktrees/235--install-on-a-clean-mac
ruby -c scripts/doctor.rb
ruby -Itest test/doctor_ruby_runtime_test.rb
```

Eight tests, zero failures, zero errors.

Then the check appears in a real full run on this machine:

```
ruby scripts/doctor.rb --agent claude 2>/dev/null | ruby -rjson -e 'JSON.parse(STDIN.read)["checks"].select { |c| c["category"] == "runtime" }.each { |c| puts "#{c["status"]}  #{c["name"]}  #{c["message"]}" }'
```

Expected on this machine (which has a modern ruby): one `pass` line naming the version and the
absolute interpreter path. If the JSON key names differ, just eyeball the raw output for
`"ruby_floor"`.

Then the full suite:

```
ruby -Itest -e 'Dir["test/*_test.rb"].each { |f| require File.expand_path(f) }'
```

There is no `Rakefile` in this repo, so `rake test` does not exist. Watch `test/doctor_test.rb`
and `test/doctor_core_test.rb`: if either asserts an exact check count or an exact category list
for the full run, update that expectation to include the new `runtime` check.

## Done when

`check_ruby_runtime` exists, is registered in `run_checks` only, its test is green, the runtime
category shows up in a real doctor run, `docs/internals.md` names it, and the full suite is green.
