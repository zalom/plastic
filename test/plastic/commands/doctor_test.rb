# frozen_string_literal: true

require_relative "installer_helper"
require_relative "../doctor/whole_home"
require_relative "../doctor/codex_home"

class DoctorCommandTest < Plastic::TestCase
  include InstallerHelper
  include WholeHome

  GATE = "a check found a problem; run the repairs named above, then run plastic doctor again"

  def setup
    super
    whole_home
    @package = fake_package(RUNNING)
  end

  def doctor(*argv, env: {}) = call("doctor", *argv, env: { "PLASTIC_PACKAGE_ROOT" => @package, "CLAUDE_CODE_SESSION_ID" => "s-1" }.merge(env))

  def test_a_call_no_harness_names_exits_2_and_names_the_option
    result = call("doctor", env: { "PLASTIC_PACKAGE_ROOT" => @package })

    assert_equal [2, true], [result.code, result.err.include?("name one with --harness: claude-code, codex, hermes")]
  end

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
    assert_match(/repair:\s+plastic install/, result.out)
    assert_includes result.err, GATE
  end

  def test_json_keeps_every_repair_as_a_list
    File.delete(File.join(claude_dir, "plastic", "VERSION"))
    File.chmod(0o644, hook_file)
    document = JSON.parse(doctor("--json").out)

    assert_equal ["plastic init", "plastic install --reinstall"], document.fetch("result").fetch("repair")
  end

  def test_an_unregistered_harness_exits_2_and_names_the_registered_harnesses
    result = doctor("--harness", "unknown")

    assert_equal 2, result.code
    assert_includes result.err, "no harness unknown; the registered harnesses are claude-code, codex, hermes"
  end

  def test_the_doctor_changes_no_file_under_the_home
    File.delete(machine_path)
    FileUtils.rm_rf(store_dir)
    before = tree_snapshot(@home)
    doctor

    assert_equal before, tree_snapshot(@home)
  end
end

class DoctorDamageCaseTest < Plastic::TestCase
  include InstallerHelper
  include WholeHome

  def setup
    super
    whole_home
    @package = fake_package(RUNNING)
  end

  def doctor(harness = "claude-code") = call("doctor", "--harness", harness, env: { "PLASTIC_PACKAGE_ROOT" => @package })

  def assert_damage(label, repair)
    result = doctor

    assert_equal 1, result.code
    assert_match(/^#{Regexp.escape(label)}:\s+(?!ok)\S/, result.out)
    assert_includes result.out.squeeze(" "), "repair: #{repair}"
    assert_includes result.err, DoctorCommandTest::GATE
  end

  def test_a_store_without_the_intents_table_names_the_project_repair
    drop_table(store_path(:work), "intents")

    assert_damage "store alpha", "plastic project new #{SLUG} #{project_dir}"
  end

  def test_a_store_without_references_db_names_the_project_repair
    File.delete(store_path(:references))

    assert_damage "store alpha", "plastic project new #{SLUG} #{project_dir}"
  end

  def test_a_missing_machine_database_names_the_reinstall
    File.delete(machine_path)

    assert_damage File.basename(machine_path), "plastic install --reinstall"
  end

  def test_a_hook_launcher_that_is_not_executable_names_the_reinstall
    File.chmod(0o644, hook_file)

    assert_damage "hook SessionStart", "plastic install --reinstall"
  end

  def test_a_global_claude_md_without_the_plastic_block_names_the_reinstall
    write(File.join(claude_dir, "CLAUDE.md"), "")

    assert_damage "CLAUDE.md", "plastic install --reinstall"
  end

  def test_a_project_claude_md_without_the_agents_line_names_the_line_to_add
    write(File.join(project_dir, "CLAUDE.md"), "")

    assert_damage "CLAUDE.md alpha", "add the line @AGENTS.md to #{project_dir}/CLAUDE.md"
  end
end

class CodexDoctorDamageCaseTest < Plastic::TestCase
  include InstallerHelper
  include CodexHome

  def setup
    super
    whole_codex
    @package = fake_package(RUNNING)
  end

  def assert_damage(label, repair)
    result = call("doctor", "--harness", "codex", env: { "PLASTIC_PACKAGE_ROOT" => @package })

    assert_equal 1, result.code
    assert_match(/^#{Regexp.escape(label)}:\s+(?!ok)\S/, result.out)
    assert_includes result.out.squeeze(" "), "repair: #{repair}"
    assert_includes result.err, DoctorCommandTest::GATE
  end

  def test_a_store_without_references_db_names_the_project_repair
    File.delete(store_path(:references))

    assert_damage "store alpha", "plastic project new #{SLUG} #{project_dir}"
  end

  def test_an_empty_codex_agents_md_names_the_reinstall
    write(File.join(codex_dir, "AGENTS.md"), "")

    assert_damage "Codex AGENTS.md", "plastic install --reinstall"
  end

  def test_a_missing_codex_record_names_init
    File.delete(codex_record)

    assert_damage "codex record", "plastic init"
  end
end

class DoctorProcessTest < Plastic::TestCase
  Pool = Plastic::Graph::Database::ConnectionPool

  # The test runs on a home of its own, and its connections close before the damage step.
  def in_own_home
    Dir.mktmpdir("doctor-process") do |root|
      @home = File.realpath(root)
      @plastic_home = File.join(@home, ".plastic")
      Plastic::Graph.create(home: @plastic_home, store: "global")
      yield
    ensure
      Pool.release(@home)
    end
  end

  def command(*argv) = plastic(*argv, table: Plastic::CLI::TABLE)

  def test_the_repair_the_doctor_names_makes_the_next_doctor_pass_that_check
    in_own_home do
      project = FileUtils.mkdir_p(File.join(@home, "alpha")).first
      found = damaged(project)
      repaired = command("project", "new", "alpha", project)

      assert_equal [1, true, 0], [found.code, found.out.include?("plastic project new alpha #{project}"), repaired.code]
      assert_match(/store alpha:\s+ok/, command("doctor", "--harness", "claude-code").out)
    end
  end

  def damaged(project)
    command("project", "new", "alpha", project)
    Pool.release(@home)
    FileUtils.rm_f(File.join(@plastic_home, "stores", "alpha", "references.db"))
    command("doctor", "--harness", "claude-code")
  end
end

class CodexDoctorCommandTest < Plastic::TestCase
  include InstallerHelper
  include CodexHome

  def setup
    super
    whole_codex
    @package = fake_package(RUNNING)
  end

  def doctor(*argv, env: {}) = call("doctor", *argv, env: { "PLASTIC_PACKAGE_ROOT" => @package }.merge(env))

  def test_an_explicit_codex_call_passes_without_claude_files
    FileUtils.rm_rf(claude_dir)
    result = doctor("--harness", "codex")

    assert_equal [0, ""], [result.code, result.err]
    assert_includes result.out, "codex record:"
    refute_includes result.out, "claude record:"
  end

  def test_an_inferred_codex_call_prints_the_core_and_codex_checks
    result = doctor(env: { "CODEX_THREAD_ID" => "thread-418" })

    assert_equal [0, ""], [result.code, result.err]
    assert_includes result.out, "codex record:"
    assert_includes result.out, "sqlite3 gem:"
  end

  def test_a_codex_json_finding_has_one_repair_and_exits_1
    File.chmod(0o644, codex_launcher)
    result = doctor("--harness", "codex", "--json")
    repairs = JSON.parse(result.out).fetch("result").fetch("repair")

    assert_equal [1, ["plastic install --reinstall"]], [result.code, repairs]
    assert_empty result.err
  end

  def test_a_damaged_codex_home_is_unchanged_after_the_doctor
    File.delete(codex_record)
    File.delete(machine_path)
    before = tree_snapshot(@home)
    result = doctor("--harness", "codex")

    assert_equal [1, before], [result.code, tree_snapshot(@home)]
    assert_includes result.err, DoctorCommandTest::GATE
  end
end
