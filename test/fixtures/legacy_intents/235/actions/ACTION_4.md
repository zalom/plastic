# ACTION_4: add the injectable ruby-resolution probe and its mechanism test

Intent: 235, Make the first install work on a clean Mac.
Satisfies: AC5, AC12. Enables ACTION_5.

## Context you need (do not go looking for it)

The doctor check added in ACTION_5 must answer one question: which `ruby` would a hook process
actually get, and does it meet the floor. A hook is launched by the agent application, not by a
login shell, so a version manager that activates on shell prompt render (mise, rbenv, asdf) may
never reach it. Bare `ruby` can still resolve to `/usr/bin/ruby` 2.6.10 long after the user
installs Ruby 3.3.

That probe must be testable with no real process spawn and no `ENV` touching, so it lives in its
own small module with an injected capture lambda. This is the house pattern already used by
`scripts/lib/power_tools.rb` (pure detectors, `doctor.rb` takes them as keyword defaults) and by
`QmdSync.default_runner` and `Doctor.default_runner` (a real `Open3.capture3` in production, a
fake in tests).

This action creates the module and its test. Its only consumer arrives in ACTION_5.

## Where you work

Worktree root:
`/Users/zlatko/apps/personal/plastic/.claude/worktrees/235--install-on-a-clean-mac`

If Edit or Write is denied or writes to the wrong tree, fall back to a Bash ruby write using
absolute paths and ` # plastic-ok` appended.

## Step 1: create `scripts/lib/ruby_probe.rb`

New file at
`/Users/zlatko/apps/personal/plastic/.claude/worktrees/235--install-on-a-clean-mac/scripts/lib/ruby_probe.rb`:

```ruby
# encoding: UTF-8
# frozen_string_literal: true

# Which ruby would a spawned Plastic hook actually get, and what version is it?
# Intent 235, D6. Pure and dependency injected: the capture seam is a lambda, so
# tests never spawn a process and never touch ENV.
#
# A hook is launched by the agent application, not by a login shell, so a version
# manager that activates on shell prompt render (mise, rbenv, asdf) may never reach
# it and bare `ruby` can still resolve to the system interpreter. Doctor reports
# that. It never repairs it.
#
# Mechanism, and why it is honest:
#   - The command word is the bare name "ruby", so the operating system resolves it
#     on the inherited PATH exactly the way it does for a spawned bash launcher. We
#     do not read PATH ourselves and we do not reimplement the search.
#   - The resolved interpreter answers for itself: RUBY_VERSION is its own version,
#     RbConfig.ruby is its own absolute path. One spawn, no guessing.
#   - RUBYOPT is cleared, matching what every Plastic launcher now does. That makes
#     this the honest simulation of the post-fix world, and it stops the probe from
#     crashing on the exact machine that most needs the report (an old ruby plus a
#     shell that exports RUBYOPT=--yjit).
module RubyProbe
  module_function

  # A hash passed as the first argument MERGES onto the inherited environment. It
  # clears nothing unless the key is present with a nil or empty value, so the nil
  # here is load bearing.
  CLEARED_ENV = { "RUBYOPT" => nil }.freeze

  PROBE_ARGS = ["-rrbconfig", "-e", "puts RUBY_VERSION; puts RbConfig.ruby"].freeze

  def default_capture
    lambda do |env, command, *args|
      require "open3"
      out, _err, status = Open3.capture3(env, command, *args)
      [out, status.success?]
    rescue Errno::ENOENT
      ["", false] # no ruby on PATH: undetectable, fail open
    end
  end

  # => { found: true, version: "3.3.5", path: "/opt/ruby/bin/ruby" }
  # => { found: false, version: nil, path: nil } on any trouble at all.
  def resolve(capture: default_capture)
    out, ok = capture.call(CLEARED_ENV, "ruby", *PROBE_ARGS)
    return not_found unless ok

    version, path = out.to_s.lines.map(&:strip).reject(&:empty?)
    return not_found if version.nil? || version.empty?

    { found: true, version: version, path: path }
  rescue StandardError
    not_found
  end

  def not_found
    { found: false, version: nil, path: nil }
  end
end
```

## Step 2: register the new file with the installer

This step is the highest-risk part of the whole intent. A file under `scripts/lib/` is NOT
installed to `~/.plastic/` unless it is listed in the core-file map in
`scripts/lib/installer_core.rb`. Miss it, and every installed `doctor.rb` raises `LoadError` on
`require_relative "lib/ruby_probe"` for every user.

Open
`/Users/zlatko/apps/personal/plastic/.claude/worktrees/235--install-on-a-clean-mac/scripts/lib/installer_core.rb`
and find the map entries around line 309 to 313.

BEFORE:
```ruby
      "scripts/lib/qmd_hook.rb" => "scripts/lib/qmd_hook.rb",
      "scripts/lib/power_tools.rb" => "scripts/lib/power_tools.rb",
```
AFTER:
```ruby
      "scripts/lib/qmd_hook.rb" => "scripts/lib/qmd_hook.rb",
      "scripts/lib/power_tools.rb" => "scripts/lib/power_tools.rb",
      "scripts/lib/ruby_probe.rb" => "scripts/lib/ruby_probe.rb",
```

Match the surrounding indentation exactly (six spaces on these entries).

Note: `scripts/lib/preflight.rb` is already in this map (around line 367), so ACTION_5's
`require_relative "lib/preflight"` needs no map change.

## Step 3: create `test/ruby_probe_test.rb`

New file at
`/Users/zlatko/apps/personal/plastic/.claude/worktrees/235--install-on-a-clean-mac/test/ruby_probe_test.rb`:

```ruby
# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"

require_relative "../scripts/lib/ruby_probe"

# Hermetic proof that the RUBYOPT clearing mechanism actually works (intent 235, AC5).
# No real process is spawned, no ENV is read or written, no eval. The capture seam is
# injected as a lambda.
#
# The fake below mirrors the behavior verified on a real machine: with RUBYOPT=--yjit
# inherited, /usr/bin/ruby 2.6.10 dies with "invalid option --yjit", while the same
# call with {"RUBYOPT" => nil} as the leading env hash succeeds. The control test
# proves the fake is genuinely sensitive, so the passing test is not vacuous.
class RubyProbeTest < Minitest::Test
  INHERITED_RUBYOPT = "--yjit"

  # A fake interpreter that dies on --yjit, exactly like Ruby 2.6 does.
  # Records every call so a test can assert what reached the child.
  def sensitive_capture(calls)
    lambda do |env, command, *args|
      calls << { env: env, command: command, args: args }
      effective = env.key?("RUBYOPT") ? env["RUBYOPT"].to_s : INHERITED_RUBYOPT
      next ["", false] if effective.include?("--yjit")

      ["2.6.10\n/usr/bin/ruby\n", true]
    end
  end

  def test_resolve_passes_a_clearing_env_hash_to_the_child_call
    calls = []
    RubyProbe.resolve(capture: sensitive_capture(calls))

    assert_equal 1, calls.size
    env = calls.first[:env]
    assert env.key?("RUBYOPT"), "the env hash must carry the RUBYOPT key, a merge clears nothing without it"
    assert_nil env["RUBYOPT"]
  end

  def test_clearing_lets_a_rubyopt_sensitive_interpreter_answer
    result = RubyProbe.resolve(capture: sensitive_capture([]))

    assert result[:found]
    assert_equal "2.6.10", result[:version]
    assert_equal "/usr/bin/ruby", result[:path]
  end

  # Control: without the clearing hash the same fake fails, so the test above proves
  # something. If this ever passes, the fake stopped being RUBYOPT sensitive.
  def test_the_same_call_without_clearing_fails_on_the_same_fake
    _out, ok = sensitive_capture([]).call({}, "ruby", "-v")

    refute ok
  end

  def test_resolve_spawns_the_bare_name_so_the_os_resolves_path
    calls = []
    RubyProbe.resolve(capture: sensitive_capture(calls))

    assert_equal "ruby", calls.first[:command]
  end

  def test_a_failing_capture_reports_not_found
    result = RubyProbe.resolve(capture: ->(*) { ["", false] })

    refute result[:found]
    assert_nil result[:version]
    assert_nil result[:path]
  end

  def test_unparseable_output_reports_not_found
    result = RubyProbe.resolve(capture: ->(*) { ["", true] })

    refute result[:found]
  end

  def test_a_raising_capture_reports_not_found_instead_of_crashing
    result = RubyProbe.resolve(capture: ->(*) { raise Errno::ENOENT, "ruby" })

    refute result[:found]
  end
end
```

## Hard rules

- No `eval`, no `ENV` read or write, no global config seam, no network, no live API call. The
  test never spawns a process.
- No added line may contain an em-dash or an en-dash.
- Do not touch `scripts/doctor.rb` in this action. That is ACTION_5.

## Verify

```
cd /Users/zlatko/apps/personal/plastic/.claude/worktrees/235--install-on-a-clean-mac
ruby -c scripts/lib/ruby_probe.rb
ruby -Itest test/ruby_probe_test.rb
```

Seven tests, zero failures, zero errors.

Then confirm the installer map change did not break the install tests, and that no test asserts a
fixed count of core files:

```
ruby -Itest test/install_sync_test.rb
ruby -Itest test/install_hooks_test.rb
```

Then the full suite:

```
ruby -Itest -e 'Dir["test/*_test.rb"].each { |f| require File.expand_path(f) }'
```

There is no `Rakefile` in this repo, so `rake test` does not exist. Use the loader command above.

Finally, a sanity run of the real probe against this machine's ruby (not a test, just proof the
production default works):

```
ruby -e 'require "./scripts/lib/ruby_probe"; p RubyProbe.resolve'
```

Expected: `{:found=>true, :version=>"3.x.y", :path=>"/.../ruby"}`.

## Done when

`scripts/lib/ruby_probe.rb` exists, is listed in the installer core-file map,
`test/ruby_probe_test.rb` is green, and the full suite is green.
