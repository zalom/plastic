require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "stringio"
require "yaml"

require_relative "../scripts/update"

# update verb: pure compute_target decision logic (intent 30a1a). The npx-exec switch is
# thin glue and not unit-tested here.
class UpdateVerbTest < Minitest::Test
  TAGS = { "alpha" => "1.0.0-alpha.19", "beta" => "1.0.0-beta.2", "latest" => "0.0.1" }.freeze

  def setup
    @home = Dir.mktmpdir("update-verb")
    @u = Update.new(package_root: ".", plastic_home: @home, version: "x")
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  def test_in_channel_next_when_higher_available
    r = @u.compute_target(installed_version: "1.0.0-alpha.18", dist_tags: TAGS)
    assert_equal :ok, r[:status]
    assert_equal "1.0.0-alpha.19", r[:target]
    assert_equal :in_channel, r[:kind]
  end

  def test_up_to_date_is_noop
    r = @u.compute_target(installed_version: "1.0.0-alpha.19", dist_tags: TAGS)
    assert_equal :up_to_date, r[:status]
  end

  def test_cross_channel_toward_stable_is_frictionless
    r = @u.compute_target(installed_version: "1.0.0-alpha.19", dist_tags: TAGS, requested_channel: "beta")
    assert_equal :ok, r[:status]
    assert_equal "1.0.0-beta.2", r[:target]
    assert_equal :cross_stable, r[:kind]
  end

  def test_cross_channel_toward_bleeding_requires_confirm
    r = @u.compute_target(installed_version: "1.0.0-beta.2", dist_tags: TAGS, requested_channel: "alpha")
    assert_equal :ok, r[:status]
    assert_equal :cross_bleeding, r[:kind]
  end

  def test_unknown_channel_when_tag_absent
    r = @u.compute_target(installed_version: "1.0.0-alpha.18", dist_tags: { "alpha" => "1.0.0-alpha.18" }, requested_channel: "beta")
    assert_equal :unknown_channel, r[:status]
  end

  # --- Post-update doctor (intent 56 introduced the full run; intent 126
  # defaults it to the fast core tier with `full:` as an explicit opt-in) ---

  # Fake doctor stub for hermetic tests: records calls to both the core tier
  # (the default post-update run) and the full tier (the `full: true` opt-in),
  # each returning its own canned result.
  class FakeDoctor
    attr_reader :core_called_with, :full_called_with

    CANNED_CORE_RESULT = {
      status: "fail",
      summary: { pass: 2, warn: 0, fail: 1, total: 3 },
    }.freeze

    CANNED_RESULT = {
      status: "warn",
      summary: { pass: 3, warn: 1, fail: 0, total: 4 },
    }.freeze

    def run_core_checks(agent_key)
      @core_called_with = agent_key
      CANNED_CORE_RESULT
    end

    def run_checks(agent_key)
      @full_called_with = agent_key
      CANNED_RESULT
    end
  end

  def test_run_post_update_doctor_defaults_to_core_tier
    fake = FakeDoctor.new
    out = StringIO.new
    result = @u.run_post_update_doctor(doctor: fake, out: out)

    assert_equal "claude", fake.core_called_with, "run_core_checks should be called with 'claude' by default"
    assert_nil fake.full_called_with, "run_checks should NOT be called on the default (core) path"
    assert_equal FakeDoctor::CANNED_CORE_RESULT, result, "should return the core doctor result hash"
  end

  def test_run_post_update_doctor_full_flag_runs_full
    fake = FakeDoctor.new
    out = StringIO.new
    result = @u.run_post_update_doctor(doctor: fake, out: out, full: true)

    assert_equal "claude", fake.full_called_with, "full: true should reach run_checks with 'claude'"
    assert_nil fake.core_called_with, "run_core_checks should NOT be called when full: true"
    assert_equal FakeDoctor::CANNED_RESULT, result, "should return the full doctor result hash"
  end

  def test_run_post_update_doctor_writes_summary_to_out
    fake = FakeDoctor.new
    out = StringIO.new
    @u.run_post_update_doctor(doctor: fake, out: out)

    output = out.string
    assert_match(/doctor/i, output, "output should mention 'doctor'")
    assert_match(/fail/, output, "output should include the overall status")
    assert_match(/pass.*2|2.*pass/i, output, "output should include pass count")
    assert_match(/fail.*1|1.*fail/i, output, "output should include fail count")
  end

  def test_run_post_update_doctor_does_not_raise_on_fail_status
    fake_fail = Class.new do
      def run_core_checks(_)
        { status: "fail", summary: { pass: 0, warn: 0, fail: 2, total: 2 } }
      end
    end.new

    out = StringIO.new
    # Must not raise regardless of fail/warn status
    result = nil
    assert_silent { result = @u.run_post_update_doctor(doctor: fake_fail, out: out) }
    assert_equal "fail", result[:status]
  end

  def test_run_post_update_doctor_swallows_exception
    raising = Class.new do
      def run_core_checks(_)
        raise RuntimeError, "malformed store file"
      end
    end.new

    out = StringIO.new
    # An exception from run_core_checks must NOT propagate — the update already succeeded.
    result = @u.run_post_update_doctor(doctor: raising, out: out)

    assert_nil result, "should return nil when the doctor raises"
    assert_match(/could not run/i, out.string, "should report that the doctor could not run")
    assert_match(/malformed store file/, out.string, "should include the error message")
  end

  # cli success path: perform_switch returning 0 must trigger post-update doctor;
  # failure path (returns 1) must not. We stub perform_switch and run_post_update_doctor
  # to stay hermetic (no npx, no real doctor).
  def test_cli_success_triggers_post_update_doctor
    u = Update.new(package_root: ".", plastic_home: @home, version: "x")

    # Stub installed_version, fetch_dist_tags, perform_switch, and run_post_update_doctor
    doctor_called = false
    u.define_singleton_method(:installed_version) { "1.0.0-alpha.18" }
    u.define_singleton_method(:fetch_dist_tags) { TAGS }
    u.define_singleton_method(:perform_switch) { |_target, _flags| 0 }
    u.define_singleton_method(:run_post_update_doctor) { |**_kwargs| doctor_called = true; nil }

    u.cli([])

    assert doctor_called, "run_post_update_doctor should be called after a successful switch"
  end

  def test_cli_failure_does_not_trigger_post_update_doctor
    u = Update.new(package_root: ".", plastic_home: @home, version: "x")

    doctor_called = false
    u.define_singleton_method(:installed_version) { "1.0.0-alpha.18" }
    u.define_singleton_method(:fetch_dist_tags) { TAGS }
    u.define_singleton_method(:perform_switch) { |_target, _flags| 1 }
    u.define_singleton_method(:run_post_update_doctor) { |**_kwargs| doctor_called = true; nil }

    u.cli([])

    refute doctor_called, "run_post_update_doctor should NOT be called after a failed switch"
  end

  # --- announce_pending_config_asks (intent 194) ---

  def write_manifest(entries)
    File.write(File.join(@home, "config_asks.yml"), YAML.dump("config_asks" => entries))
  end

  def write_global_config(data)
    File.write(File.join(@home, "config.yml"), YAML.dump(data))
  end

  def sample_config_ask_entry
    {
      "id" => "advisor-default",
      "key" => "advisor.claude.default",
      "introduced" => "1.3.0",
      "question" => "Which advisor should be the default?",
      "options" => [
        { "label" => "Faux Fable", "value" => "plastic-faux-advisor" },
        { "label" => "Fable 5", "value" => "plastic-advisor" },
      ],
    }
  end

  def test_announce_prints_nothing_when_no_config_asks_yml
    # No config_asks.yml written into @home at all -- a legitimate quiet
    # no-op, distinct from a manifest that exists but cannot be read.
    buf = StringIO.new
    @u.announce_pending_config_asks(out: buf)

    assert_empty buf.string
  end

  # Fix round: an unreadable manifest must still print SOMETHING (the
  # problem itself), never nothing -- a silent no-op there would look
  # identical to "no manifest at all", hiding a broken install from the
  # one moment update.rb runs fresh code and could tell the user.
  def test_announce_prints_manifest_error_when_malformed
    File.write(File.join(@home, "config_asks.yml"), "not: valid: yaml: [")

    buf = StringIO.new
    @u.announce_pending_config_asks(out: buf)

    refute_empty buf.string, "an unreadable manifest must print something, not nothing"
    assert_match(/config_asks\.yml/, buf.string)
  end

  def test_announce_prints_pending_question_and_commands
    write_manifest([sample_config_ask_entry])
    # No config.yml -- key is unset, so the entry is pending.

    buf = StringIO.new
    @u.announce_pending_config_asks(out: buf)

    output = buf.string
    assert_match(/Which advisor should be the default\?/, output)
    assert_match(/Faux Fable/, output)
    assert_match(/Fable 5/, output)
    assert_match(/write-config advisor\.claude\.default plastic-faux-advisor/, output)
    assert_match(/write-config advisor\.claude\.default plastic-advisor/, output)
    assert_match(/write-config config_asks_dismissed --push advisor-default/, output)
  end

  def test_announce_silent_when_key_already_set
    write_manifest([sample_config_ask_entry])
    write_global_config("advisor" => { "claude" => { "default" => "plastic-advisor" } })

    buf = StringIO.new
    @u.announce_pending_config_asks(out: buf)

    assert_empty buf.string
  end

  def test_announce_rescues_and_does_not_raise
    raising = Class.new(Update) do
      def plastic_home
        raise RuntimeError, "malformed config_asks.yml"
      end
    end.new(package_root: ".", plastic_home: @home, version: "x")

    buf = StringIO.new
    assert_silent do
      # StringIO writes don't touch stdout, so assert_silent only guards
      # against an uncaught raise reaching the caller.
      raising.announce_pending_config_asks(out: buf)
    end

    assert_match(/could not check config asks/i, buf.string)
    assert_match(/malformed config_asks\.yml/, buf.string)
  end

  def test_cli_calls_announce_before_doctor_on_success
    u = Update.new(package_root: ".", plastic_home: @home, version: "x")

    call_order = []
    u.define_singleton_method(:installed_version) { "1.0.0-alpha.18" }
    u.define_singleton_method(:fetch_dist_tags) { TAGS }
    u.define_singleton_method(:perform_switch) { |_target, _flags| 0 }
    u.define_singleton_method(:announce_pending_config_asks) { |**_kwargs| call_order << :announce }
    u.define_singleton_method(:run_post_update_doctor) { |**_kwargs| call_order << :doctor; nil }

    result = u.cli([])

    assert_equal [:announce, :doctor], call_order,
      "announce_pending_config_asks must run before run_post_update_doctor"
    assert_equal 0, result, "cli's return value must be unaffected by either call"
  end

  def test_cli_passes_the_matching_agent_key_to_announce
    u = Update.new(package_root: ".", plastic_home: @home, version: "x")

    received_agent_key = nil
    u.define_singleton_method(:installed_version) { "1.0.0-alpha.18" }
    u.define_singleton_method(:fetch_dist_tags) { TAGS }
    u.define_singleton_method(:perform_switch) { |_target, _flags| 0 }
    u.define_singleton_method(:announce_pending_config_asks) { |agent_key:, **_kwargs| received_agent_key = agent_key }
    u.define_singleton_method(:run_post_update_doctor) { |**_kwargs| nil }

    u.cli(["--codex"])

    assert_equal "codex", received_agent_key,
      "cli should pass the agent it is actually installing for, not always the default claude"
  end

  # --- Fix round: agent scoping actually wired through announce ---

  def test_announce_silent_for_entry_scoped_to_a_different_agent
    write_manifest([sample_config_ask_entry.merge("agents" => ["codex"])])
    # No config.yml -- key unset, so the entry would be pending if it applied.

    buf = StringIO.new
    @u.announce_pending_config_asks(agent_key: "claude", out: buf)

    assert_empty buf.string, "an entry scoped to codex must not be announced for claude"
  end

  def test_announce_prints_for_entry_scoped_to_matching_agent
    write_manifest([sample_config_ask_entry.merge("agents" => ["codex"])])

    buf = StringIO.new
    @u.announce_pending_config_asks(agent_key: "codex", out: buf)

    assert_match(/Which advisor should be the default\?/, buf.string)
  end

  def test_cli_skips_announce_on_failed_switch
    u = Update.new(package_root: ".", plastic_home: @home, version: "x")

    announced = false
    u.define_singleton_method(:installed_version) { "1.0.0-alpha.18" }
    u.define_singleton_method(:fetch_dist_tags) { TAGS }
    u.define_singleton_method(:perform_switch) { |_target, _flags| 1 }
    u.define_singleton_method(:announce_pending_config_asks) { |**_kwargs| announced = true }
    u.define_singleton_method(:run_post_update_doctor) { |**_kwargs| nil }

    u.cli([])

    refute announced, "announce_pending_config_asks should NOT be called after a failed switch"
  end
end
