require "minitest/autorun"
require "tmpdir"
require "fileutils"

require_relative "../scripts/update"

# update verb: pure compute_target decision logic (intent 30a1a). The npx-exec switch is
# thin glue and not unit-tested here.
class UpdateVerbTest < Minitest::Test
  TAGS = { "alpha" => "1.0.0-alpha.19", "beta" => "1.0.0-beta.2", "latest" => "0.0.1" }.freeze

  def setup
    @home = Dir.mktmpdir("update-verb")
    @u = Update.new(package_root: ".", plastic_home: @home, version: "x")
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  def test_in_channel_next_when_higher_available
    r = @u.compute_target(installed_version: "1.0.0-alpha.18", dist_tags: TAGS)
    assert_equal :ok, r[:status]
    assert_equal "1.0.0-alpha.19", r[:target]
    assert_equal :in_channel, r[:kind]
  end

  def test_up_to_date_is_noop
    r = @u.compute_target(installed_version: "1.0.0-alpha.19", dist_tags: TAGS)
    assert_equal :up_to_date, r[:status]
  end

  def test_cross_channel_toward_stable_is_frictionless
    r = @u.compute_target(installed_version: "1.0.0-alpha.19", dist_tags: TAGS, requested_channel: "beta")
    assert_equal :ok, r[:status]
    assert_equal "1.0.0-beta.2", r[:target]
    assert_equal :cross_stable, r[:kind]
  end

  def test_cross_channel_toward_bleeding_requires_confirm
    r = @u.compute_target(installed_version: "1.0.0-beta.2", dist_tags: TAGS, requested_channel: "alpha")
    assert_equal :ok, r[:status]
    assert_equal :cross_bleeding, r[:kind]
  end

  def test_unknown_channel_when_tag_absent
    r = @u.compute_target(installed_version: "1.0.0-alpha.18", dist_tags: { "alpha" => "1.0.0-alpha.18" }, requested_channel: "beta")
    assert_equal :unknown_channel, r[:status]
  end
end
