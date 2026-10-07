# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require "tmpdir"
require_relative "../scripts/lib/installer_core"
require_relative "varar/support/kernel_command"

# What an install or an update repairs in the stores of a home that already has them.
class InstallerCoreRepairTest < Minitest::Test
  EMPTY_INDEX = "# Index\n\n## Active\n\n## Waiting\n\n## Done\n\n## Dropped\n"
  LISTED_INDEX = "# Index\n\n## Active\n\n- 1 first\n"

  def setup
    @home = Dir.mktmpdir("installer-repair")
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  def plastic_home = File.join(@home, ".plastic")

  def stores(*parts) = File.join(plastic_home, "stores", *parts)

  def global(*parts) = stores("global", *parts)

  def installer = InstallerCore.new(package_root: Dir.pwd, plastic_home:)

  def repair = capture_io { installer.repair_stores }

  def test_a_first_install_creates_no_projects_folder
    capture_io { installer.bootstrap }

    assert_equal ["global"], Dir.children(stores)
  end

  def test_an_empty_stray_projects_folder_is_removed
    FileUtils.mkdir_p(stores("projects"))
    repair

    refute_path_exists stores("projects")
  end

  def test_a_stray_projects_folder_that_holds_something_stays_and_is_reported
    FileUtils.mkdir_p(stores("projects", "kept"))
    out, = repair

    assert_equal [true, true], [Dir.exist?(stores("projects", "kept")), out.include?(stores("projects"))]
  end

  def test_a_global_index_of_headings_only_is_removed_and_the_store_made_ready
    FileUtils.mkdir_p(global)
    File.write(global("INDEX.md"), EMPTY_INDEX)
    repair
    call = KernelCommand.new(@home).run("intent", "new", "First")

    assert_equal [false, 0], [File.exist?(global("INDEX.md")), call.code]
  end

  def test_a_global_index_that_lists_an_intent_stays_byte_for_byte
    FileUtils.mkdir_p(global)
    File.binwrite(global("INDEX.md"), LISTED_INDEX)
    repair

    assert_equal LISTED_INDEX, File.binread(global("INDEX.md"))
  end

  def test_a_global_index_of_headings_only_over_intent_folders_stays
    FileUtils.mkdir_p(global("store", "1--first"))
    File.write(global("INDEX.md"), EMPTY_INDEX)
    repair

    assert_equal EMPTY_INDEX, File.read(global("INDEX.md"))
  end

  def test_a_reinstall_makes_a_launcher_that_lost_its_executable_bit_executable_again
    capture_io { installer.distribute(:install, tmp_dirs: []) }
    launcher = File.join(plastic_home, "bin", "plastic")
    File.chmod(0o644, launcher)
    capture_io { installer.distribute(:update, tmp_dirs: []) }

    assert File.executable?(launcher), "#{launcher} is not executable after the reinstall"
  end

  def test_a_legacy_home_is_left_alone
    FileUtils.mkdir_p(File.join(plastic_home, "projects"))
    File.write(File.join(plastic_home, "INDEX.md"), EMPTY_INDEX)
    repair

    assert_equal [true, true], [File.exist?(File.join(plastic_home, "INDEX.md")), Dir.exist?(File.join(plastic_home, "projects"))]
  end
end
