# frozen_string_literal: true

require_relative "../commands/installer_helper"

class ReleaseUpdateTest < Plastic::TestCase
  include InstallerHelper

  def test_an_updated_release_starts_the_ruby_plastic_ruby_names
    developer_ruby = File.join(@home, "developer-ruby")
    File.symlink(RbConfig.ruby, developer_ruby)
    result = update_to("99.0.0-alpha.2", "PLASTIC_RUBY" => developer_ruby)

    assert_equal 0, result.code, result.err
    assert_includes active_launcher, "exec #{developer_ruby} --disable-gems -rrbconfig"
  end

  def test_a_release_without_pins_runs_on_the_ruby_that_updates_it
    result = update_to("99.0.0-alpha.2")

    assert_equal 0, result.code, result.err
    assert_includes active_launcher, "exec #{RbConfig.ruby} --disable-gems -rrbconfig"
  end

  private

  def update_to(version, env = {})
    installed("99.0.0-alpha.1")
    activated("99.0.0-alpha.1")
    call("update", env: env.merge("PLASTIC_PACKAGE_ROOT" => fake_package("99.0.0-alpha.1"), "PLASTIC_LOCAL_RELEASE" => local_release(version)))
  end

  def active_launcher = File.read(File.join(share, "active", "bin", "plastic"))
end
