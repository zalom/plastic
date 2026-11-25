# frozen_string_literal: true

require "minitest/autorun"

class ShippedTextGuardTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SUBJECTS = Dir[File.join(ROOT, "agents", "**", "*")].select { |path| File.file?(path) }
  REMOVED = /(?<![\w-])(?:plan|checklist)\.md|--slug|ID--slug\.md/

  def removed_names(text) = text.scan(REMOVED)

  def test_the_subjects_are_read_from_the_disk
    refute_empty SUBJECTS
    assert(SUBJECTS.any? { |path| path.include?("/agents/plastic-executor.md") })
  end

  def test_no_shipped_file_names_a_removed_file_or_option
    found = SUBJECTS.to_h { |path| [path.delete_prefix("#{ROOT}/"), removed_names(File.read(path))] }.reject { |_, names| names.empty? }

    assert_empty found
  end

  def test_the_detector_catches_a_plan_file
    assert_equal ["plan.md"], removed_names("Write plan.md first.")
  end

  def test_the_detector_catches_a_checklist_file
    assert_equal ["checklist.md"], removed_names("check off `checklist.md`")
  end

  def test_the_detector_catches_the_slug_option
    assert_equal ["--slug"], removed_names("plastic intent new TITLE --slug x")
  end

  def test_the_detector_catches_the_slug_named_file
    assert_equal ["ID--slug.md"], removed_names("born in ID--slug.md")
  end

  def test_the_detector_leaves_a_report_plan_template_alone
    assert_empty removed_names("render templates/report-plan.md and the roadmap plan")
  end

  def test_the_deleted_plan_template_does_not_ship
    refute_path_exists File.join(ROOT, "templates", "plan.md")
  end

  def test_the_deleted_checklist_template_does_not_ship
    refute_path_exists File.join(ROOT, "templates", "checklist.md")
  end
end
