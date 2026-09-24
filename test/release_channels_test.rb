require "minitest/autorun"
require_relative "../scripts/lib/release_channels"

# G5 (intent 391): ReleaseChannels turns a GitHub releases list into the newest
# version per channel, the shape select-update-target and Update#compute_target
# already expect (the same Hash a dist-tags call used to produce). Hermetic:
# every test feeds a plain releases array, never a real HTTP call.
class ReleaseChannelsTest < Minitest::Test
  def test_a_draft_release_is_skipped
    releases = [
      { "tag_name" => "v9.9.9", "draft" => true },
      { "tag_name" => "v1.0.0", "draft" => false },
    ]

    assert_equal({ "latest" => "1.0.0" }, ReleaseChannels.channels(releases))
  end

  def test_a_prerelease_with_no_alpha_or_beta_marker_counts_as_stable
    releases = [
      { "tag_name" => "v1.0.0-rc.1", "draft" => false, "prerelease" => true },
    ]

    assert_equal({ "latest" => "1.0.0-rc.1" }, ReleaseChannels.channels(releases))
  end

  def test_alpha_and_beta_tags_sort_into_their_own_channels
    releases = [
      { "tag_name" => "v2.0.0-alpha.5", "draft" => false },
      { "tag_name" => "v2.0.0-beta.1", "draft" => false },
      { "tag_name" => "v1.14.1", "draft" => false },
    ]

    result = ReleaseChannels.channels(releases)
    assert_equal "2.0.0-alpha.5", result["alpha"]
    assert_equal "2.0.0-beta.1", result["beta"]
    assert_equal "1.14.1", result["latest"]
  end

  def test_keeps_the_newest_release_per_channel
    releases = [
      { "tag_name" => "v2.0.0-alpha.1", "draft" => false },
      { "tag_name" => "v2.0.0-alpha.5", "draft" => false },
      { "tag_name" => "v2.0.0-alpha.3", "draft" => false },
    ]

    assert_equal({ "alpha" => "2.0.0-alpha.5" }, ReleaseChannels.channels(releases))
  end

  def test_a_malformed_tag_is_skipped_not_raised
    releases = [
      { "tag_name" => "not-a-version", "draft" => false },
      { "tag_name" => "v1.0.0", "draft" => false },
    ]

    assert_equal({ "latest" => "1.0.0" }, ReleaseChannels.channels(releases))
  end

  def test_empty_releases_list_returns_an_empty_hash
    assert_equal({}, ReleaseChannels.channels([]))
  end

  def test_symbol_keys_work_the_same_as_string_keys
    releases = [{ tag_name: "v1.0.0", draft: false }]

    assert_equal({ "latest" => "1.0.0" }, ReleaseChannels.channels(releases))
  end
end
