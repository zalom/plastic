# frozen_string_literal: true

require "minitest/autorun"
require_relative "../scripts/lib/release_channels"

class ReleaseChannelsTest < Minitest::Test
  def order(*versions) = versions.sort { |left, right| ReleaseChannels.compare(ReleaseChannels.parse(left), ReleaseChannels.parse(right)) }

  def test_a_version_that_is_not_semver_parses_to_nil
    assert_equal [nil, nil], [ReleaseChannels.parse("2.0"), ReleaseChannels.parse("v2.0.3")]
  end

  def test_versions_order_by_semver_precedence
    assert_equal %w[1.9.0 2.0.0 2.0.10 2.1.0], order("2.1.0", "2.0.10", "1.9.0", "2.0.0")
  end

  def test_pre_releases_order_before_the_release_and_by_their_segments
    expected = %w[2.0.0-alpha 2.0.0-alpha.2 2.0.0-alpha.10 2.0.0-alpha.beta 2.0.0-beta.1 2.0.0]

    assert_equal expected, order(*expected.reverse)
  end

  def test_the_tag_names_its_channel
    assert_equal %w[alpha beta latest], %w[v2.0.0-alpha.3 v2.0.0-beta.1 v2.0.3].map { |tag| ReleaseChannels.channel(tag) }
  end

  def test_the_newest_release_of_each_channel_is_kept
    releases = [{ "tag_name" => "v2.0.2" }, { "tag_name" => "v2.0.3" }, { tag_name: "v2.1.0-alpha.2" }, { tag_name: "v2.1.0-alpha.1" }]

    assert_equal({ "latest" => "2.0.3", "alpha" => "2.1.0-alpha.2" }, ReleaseChannels.channels(releases))
  end

  def test_drafts_missing_tags_and_bad_versions_are_skipped
    releases = [{ "tag_name" => "v9.0.0", "draft" => true }, { draft: false }, { "tag_name" => "nightly" }, { "tag_name" => "v2.0.3" }]

    assert_equal({ "latest" => "2.0.3" }, ReleaseChannels.channels(releases))
  end
end
