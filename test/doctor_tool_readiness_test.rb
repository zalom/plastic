require "minitest/autorun"
require "tmpdir"
require "fileutils"

require_relative "../scripts/doctor"

# Hermetic tests for doctor's tool-readiness checks (intent 221, D4): check_serena and
# check_enola wrap PowerTools' existing pure detectors. Both checks are two-state (pass on
# present, pass on absent with a note); neither ever warns or fails, so every fixture below
# asserts status: "pass".
class DoctorToolReadinessTest < Minitest::Test
  def setup
    @cwd = Dir.mktmpdir("plastic-doctor-tool-readiness")
  end

  def teardown
    FileUtils.rm_rf(@cwd)
  end

  def doctor
    Doctor.new(plastic_home: Dir.mktmpdir("plastic-doctor-home"))
  end

  def absent_probe
    ->(*) { false }
  end

  def present_probe
    ->(*) { true }
  end

  def by_name(checks, name)
    checks.find { |c| c[:name] == name }
  end

  def test_serena_marker_dir_present_passes_as_available
    FileUtils.mkdir_p(File.join(@cwd, ".serena"))

    checks = doctor.check_serena(cwd: @cwd, path_probe: absent_probe)
    ready = by_name(checks, "serena_ready")

    assert_equal "pass", ready[:status]
    assert_includes ready[:message], "available"
  end

  def test_serena_absent_everywhere_passes_as_not_installed
    checks = doctor.check_serena(cwd: @cwd, path_probe: absent_probe)
    ready = by_name(checks, "serena_ready")

    assert_equal "pass", ready[:status]
    assert_includes ready[:message], "not installed"
  end

  def test_serena_on_path_passes_as_available
    checks = doctor.check_serena(cwd: @cwd, path_probe: present_probe)
    ready = by_name(checks, "serena_ready")

    assert_equal "pass", ready[:status]
    assert_includes ready[:message], "available"
  end

  def test_enola_marker_dir_present_passes_as_available
    FileUtils.mkdir_p(File.join(@cwd, ".enola"))

    checks = doctor.check_enola(cwd: @cwd, path_probe: absent_probe)
    ready = by_name(checks, "enola_ready")

    assert_equal "pass", ready[:status]
    assert_includes ready[:message], "available"
  end

  def test_enola_absent_everywhere_passes_as_not_installed
    checks = doctor.check_enola(cwd: @cwd, path_probe: absent_probe)
    ready = by_name(checks, "enola_ready")

    assert_equal "pass", ready[:status]
    assert_includes ready[:message], "not installed"
  end

  def test_neither_check_ever_warns_or_fails
    all = doctor.check_serena(cwd: @cwd, path_probe: absent_probe) +
          doctor.check_enola(cwd: @cwd, path_probe: absent_probe)

    assert(all.all? { |c| c[:status] == "pass" },
      "expected every tool-readiness check to be pass, got: #{all.map { |c| [c[:name], c[:status]] }}")
  end
end
