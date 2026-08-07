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
