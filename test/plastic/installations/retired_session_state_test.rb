# frozen_string_literal: true

require_relative "../../test_helper"
require "plastic/installations/retired_session_state"

class RetiredSessionStateTest < Plastic::TestCase
  Retired = Plastic::Installations::RetiredSessionState

  def session(name = "s1") = File.join(Plastic::StoreLayout.global_store(@plastic_home), ".tmp", name)

  def leftover(name = "s1")
    FileUtils.mkdir_p(session(name))
    File.write(File.join(session(name), "current"), "x")
    File.join(session(name), "current")
  end

  def test_the_folders_are_plastic_tmp_alone_when_it_is_set
    assert_equal [File.join(@home, "chosen")], Retired.folders(File.join(@home, "chosen"))
  end

  def test_the_folders_are_the_temp_folder_of_the_system_and_tmp_when_plastic_tmp_is_empty
    assert_equal [Dir.tmpdir, "/tmp"].uniq, Retired.folders("")
  end

  def test_a_current_pointer_under_a_store_is_removed_and_counted
    file = leftover

    assert_equal [1, false], [Retired.new(@plastic_home, []).call, File.exist?(file)]
  end

  def test_a_leftover_in_a_tmp_folder_is_removed_by_its_name
    tmp = File.join(@home, "tmp")
    FileUtils.mkdir_p(tmp)
    File.write(File.join(tmp, "plastic-abc--def.json"), "{")
    File.write(File.join(tmp, "other.json"), "{")

    assert_equal [1, ["other.json"]], [Retired.new(@plastic_home, [tmp]).call, Dir.children(tmp)]
  end

  def test_a_symlinked_session_folder_is_never_followed
    target = File.join(@home, "elsewhere")
    FileUtils.mkdir_p(target)
    File.write(File.join(target, "current"), "x")
    FileUtils.mkdir_p(File.dirname(session))
    File.symlink(target, session)

    assert_equal [0, true], [Retired.new(@plastic_home, []).call, File.exist?(File.join(target, "current"))]
  end

  def test_a_missing_tmp_folder_is_skipped
    assert_equal 0, Retired.new(@plastic_home, [File.join(@home, "absent")]).call
  end

  def test_a_leftover_that_cannot_be_deleted_is_named_in_a_warning
    file = leftover
    File.chmod(0o555, session)
    _, err = capture_io { Retired.new(@plastic_home, []).call }

    assert_includes err, "   Could not remove retired session state #{file}"
  ensure
    File.chmod(0o755, session)
  end

  def test_a_session_folder_without_a_current_pointer_counts_nothing
    FileUtils.mkdir_p(session)

    assert_equal 0, Retired.new(@plastic_home, []).call
  end

  def test_a_tmp_entry_that_is_a_file_is_skipped
    FileUtils.mkdir_p(Plastic::StoreLayout.global_store(@plastic_home))
    File.write(File.join(Plastic::StoreLayout.global_store(@plastic_home), ".tmp"), "x")

    assert_equal 0, Retired.new(@plastic_home, []).call
  end

  def test_a_candidate_that_is_a_folder_is_skipped
    FileUtils.mkdir_p(File.join(session, "current"))

    assert_equal 0, Retired.new(@plastic_home, []).call
  end
end
