# frozen_string_literal: true

require_relative "../commands/installer_helper"
require_relative "../../../scripts/lib/plastic/workflows/show_version"

class WorkflowShowVersionTest < Plastic::TestCase
  include InstallerHelper

  def show(root) = run_workflow(Plastic::Workflows::ShowVersion, harness: scoped_harness(env: { "PLASTIC_PACKAGE_ROOT" => root }))

  def test_the_package_json_version_and_its_channel_are_printed
    root = fake_package("9.1.0-beta.2")

    outcome, context = show(root)

    assert_equal :done, outcome
    assert_equal [["version:", "9.1.0-beta.2"], ["channel:", "beta"], ["source:", File.join(root, "package.json")]], printed_rows(context)
  end

  def test_a_version_file_wins_over_package_json
    root = fake_package("9.1.0")
    File.write(File.join(root, "VERSION"), "9.2.0\n")

    assert_equal "9.2.0", printed_row(show(root).last, "version:")
  end

  def test_a_package_with_no_version_source_fails_the_call
    outcome, = show(FileUtils.mkdir_p(File.join(@home, "empty")).first)

    assert_equal "code_show_version, gate: the running package has no VERSION file and no package.json", outcome.message
  end
end
