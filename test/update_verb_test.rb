require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "stringio"

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
end
