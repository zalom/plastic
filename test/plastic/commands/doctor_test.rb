# frozen_string_literal: true

require_relative "installer_helper"
require_relative "../doctor/whole_home"
require_relative "../../varar/support/kernel_command"

class DoctorCommandTest < Plastic::TestCase
  include InstallerHelper
  include WholeHome

  GATE = "a check found a problem; run the repairs named above, then run plastic doctor again"

  def setup
    super
    whole_home
    @package = fake_package(RUNNING)
  end

  def doctor(*argv, env: {}) = call("doctor", *argv, env: { "PLASTIC_PACKAGE_ROOT" => @package }.merge(env))

  def test_a_whole_home_prints_ok_rows_and_exits_0
    result = doctor

    assert_equal [0, ""], [result.code, result.err]
    assert_match(/version:\s+ok, #{RUNNING}/, result.out)
    refute_includes result.out, "repair:"
  end

  def test_a_finding_prints_its_repair_and_exits_1_with_the_gate_line
    File.delete(machine_path)
    result = doctor

    assert_equal 1, result.code
    assert_match(/repair:\s+plastic next/, result.out)
    assert_includes result.err, GATE
  end

  def test_json_keeps_every_repair_as_a_list
    File.delete(machine_path)
    File.chmod(0o644, hook_file)
    document = JSON.parse(doctor("--json").out)

    assert_equal ["plastic next", "plastic install --claude --reinstall"], document.fetch("result").fetch("repair")
  end

  def test_a_harness_with_no_module_exits_2_and_names_claude_code
    result = doctor("--harness", "codex")

    assert_equal 2, result.code
    assert_includes result.err, "harnesses with one: claude-code"
  end

  def test_the_doctor_changes_no_file_under_the_home
    File.delete(machine_path)
    FileUtils.rm_rf(store_dir)
    before = tree_snapshot(@home)
    doctor

    assert_equal before, tree_snapshot(@home)
  end
end

class DoctorProcessTest < Minitest::Test
  def test_the_repair_the_doctor_names_makes_the_next_doctor_pass_that_check
    Dir.mktmpdir("doctor-process") do |home|
      kernel = KernelCommand.new(home)
      project = FileUtils.mkdir_p(File.join(home, "alpha")).first
      found = damaged(kernel, project)
      kernel.run!("project", "new", "alpha", project)

      assert_equal [1, true], [found.code, found.out.include?("plastic project new alpha #{project}")]
      assert_match(/store alpha:\s+ok/, kernel.run("doctor").out)
    end
  end

  def damaged(kernel, project)
    kernel.run!("project", "new", "alpha", project)
    FileUtils.rm_f(File.join(kernel.plastic_home, "stores", "alpha", "references.db"))
    kernel.run("doctor")
  end
end
