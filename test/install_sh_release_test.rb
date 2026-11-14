# frozen_string_literal: true

require_relative "support/install_sh_helper"

# install.sh refuses a release before it installs anything: a checksum that does not match, an archive
# that holds a link, a download address given by the environment. A dry run changes nothing. It
# installs the Ruby that its own check resolved. Each test runs in a throwaway home with a small
# release that a folder serves, so no network is reached and no Plastic is set up.
class InstallShReleaseTest < Minitest::Test
  include InstallShHelper

  def test_a_wrong_checksum_is_refused_and_nothing_is_installed
    directory = release("9.9.9")
    File.binwrite(File.join(directory, "plastic.tgz"), "tampered", mode: "a")
    out, err, status = install(PLASTIC_LOCAL_RELEASE: directory)

    assert_equal [1, true], [status.exitstatus, err.include?("plastic.tgz does not match its published checksum")]
    assert_empty out.lines.grep(/is active/)
    assert_untouched
  end

  def test_an_archive_that_holds_a_link_is_refused_and_nothing_is_installed
    directory = release("9.9.9") { |package| File.symlink("/etc/hosts", File.join(package, "hosts")) }
    _out, err, status = install(PLASTIC_LOCAL_RELEASE: directory)

    assert_equal [1, true], [status.exitstatus, err.include?("a link or a special file")]
    assert_untouched
  end

  def test_a_download_address_from_the_environment_is_refused_and_nothing_is_installed
    out, err, status = install(PLASTIC_ARCHIVE_URL: "https://example.invalid/plastic.tgz")

    assert_equal [1, "", true], [status.exitstatus, out, err.include?("PLASTIC_ARCHIVE_URL is not read")]
    assert_untouched
  end

  def test_a_dry_run_says_what_it_would_do_and_changes_nothing
    out, _err, status = install("--dry-run", PLASTIC_LOCAL_RELEASE: release("9.9.9"))

    assert_equal 0, status.exitstatus
    assert_includes out, "would install Plastic 9.9.9 under #{share}"
    assert_untouched
  end

  def test_a_ruby_given_by_name_is_installed_by_its_full_path
    File.symlink(RbConfig.ruby, File.join(@fakebin, "ruby"))
    _out, err, status = install_local("9.9.9", PLASTIC_RUBY: "ruby")

    assert_equal [0, ""], [status.exitstatus, err]
    assert_includes File.read(launcher), "exec #{File.join(@fakebin, "ruby")}"
  end

  private

  def assert_untouched
    assert_equal [false, false], [File.exist?(share), File.exist?(launcher)]
  end
end
