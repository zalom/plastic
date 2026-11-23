# frozen_string_literal: true

require_relative "../../../commands/installer_helper"
require_relative "../../../../../lib/plastic/workflows/code/update"
require_relative "../../../../../lib/plastic/workflows/code/update/preview"

# A local release folder (development mode) that cannot be read: both runs name
# the folder in a plain message and carry no class name.
class LocalReleaseUpdateTest < Plastic::TestCase
  include InstallerHelper

  def test_a_dry_run_names_a_folder_that_does_not_exist
    folder = File.join(@home, "missing-release")

    assert_plain_folder_message folder, dry_run_error(folder)
  end

  def test_a_dry_run_names_the_folder_whose_manifest_cannot_be_read
    folder = local_release("2.0.7")
    File.chmod(0o000, File.join(folder, "plastic.manifest.json"))

    assert_plain_folder_message folder, dry_run_error(folder)
  ensure
    File.chmod(0o600, File.join(folder, "plastic.manifest.json")) if folder
  end

  def test_a_dry_run_names_the_folder_that_itself_cannot_be_read
    folder = local_release("2.0.7")
    File.chmod(0o000, folder)

    assert_plain_folder_message folder, dry_run_error(folder)
  ensure
    File.chmod(0o700, folder) if folder
  end

  def test_a_real_run_names_a_folder_that_does_not_exist
    folder = File.join(@home, "missing-release")

    assert_plain_folder_message folder, real_run_error(folder)
  end

  def test_a_real_run_names_the_folder_whose_manifest_cannot_be_read
    folder = local_release("99.0.0-alpha.2")
    File.chmod(0o000, File.join(folder, "plastic.manifest.json"))

    assert_plain_folder_message folder, real_run_error(folder)
  ensure
    File.chmod(0o600, File.join(folder, "plastic.manifest.json")) if folder
  end

  def test_a_real_run_names_the_folder_that_has_no_archive
    folder = local_release("99.0.0-alpha.2")
    File.delete(File.join(folder, "plastic.tgz"))

    assert_plain_folder_message folder, real_run_error(folder)
  end

  private

  def dry_run_error(folder)
    installed("2.0.5")
    activated("2.0.5")
    harness = scoped_harness(env: { "PLASTIC_PACKAGE_ROOT" => fake_package("2.0.5"), "PLASTIC_SHARE" => share, "PLASTIC_LOCAL_RELEASE" => folder })
    assert_raises(Plastic::Failed) { run_workflow(Plastic::Workflows::Code::Update::Preview, harness:, dry_run: true, channel: nil) }
  end

  def real_run_error(folder)
    installed("99.0.0-alpha.1")
    activated("99.0.0-alpha.1")
    harness = scoped_harness(env: { "PLASTIC_PACKAGE_ROOT" => fake_package("99.0.0-alpha.1"), "PLASTIC_SHARE" => share, "PLASTIC_LOCAL_RELEASE" => folder })
    assert_raises(Plastic::Failed) { run_workflow(Plastic::Workflows::Code::Update, harness:, channel: nil) }
  end

  def assert_plain_folder_message(folder, error)
    assert_match(/\Acannot read the local release folder #{Regexp.escape(folder)}/, error.message)
    refute_match(/\b[A-Z]\w*(::\w+)+/, error.message)
  end
end
