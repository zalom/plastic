require "minitest/autorun"
require_relative "../scripts/lib/release_channels"

# G5 (intent 391): ReleaseChannels turns a GitHub releases list into the newest
# version per channel, the shape select-update-target and Update#compute_target
# already expect (the same Hash a dist-tags call used to produce). Hermetic:
# every test feeds a plain releases array, never a real HTTP call.
class ReleaseChannelsTest < Minitest::Test
  def test_a_draft_release_is_skipped
    releases = [
      {"tag_name" => "v9.9.9", "draft" => true},
      {"tag_name" => "v1.0.0", "draft" => false}
    ]

    assert_equal({"latest" => "1.0.0"}, ReleaseChannels.channels(releases))
  end

  def test_a_prerelease_with_no_alpha_or_beta_marker_counts_as_stable
    releases = [
      {"tag_name" => "v1.0.0-rc.1", "draft" => false, "prerelease" => true}
    ]

    assert_equal({"latest" => "1.0.0-rc.1"}, ReleaseChannels.channels(releases))
  end

  def test_alpha_and_beta_tags_sort_into_their_own_channels
    releases = [
      {"tag_name" => "v2.0.0-alpha.5", "draft" => false},
      {"tag_name" => "v2.0.0-beta.1", "draft" => false},
      {"tag_name" => "v1.14.1", "draft" => false}
    ]

    result = ReleaseChannels.channels(releases)

    assert_equal "2.0.0-alpha.5", result["alpha"]
    assert_equal "2.0.0-beta.1", result["beta"]
    assert_equal "1.14.1", result["latest"]
  end

  def test_keeps_the_newest_release_per_channel
    releases = [
      {"tag_name" => "v2.0.0-alpha.1", "draft" => false},
      {"tag_name" => "v2.0.0-alpha.5", "draft" => false},
      {"tag_name" => "v2.0.0-alpha.3", "draft" => false}
    ]

    assert_equal({"alpha" => "2.0.0-alpha.5"}, ReleaseChannels.channels(releases))
  end

  def test_a_malformed_tag_is_skipped_not_raised
    releases = [
      {"tag_name" => "not-a-version", "draft" => false},
      {"tag_name" => "v1.0.0", "draft" => false}
    ]

    assert_equal({"latest" => "1.0.0"}, ReleaseChannels.channels(releases))
  end

  def test_empty_releases_list_returns_an_empty_hash
    assert_equal({}, ReleaseChannels.channels([]))
  end

  def test_symbol_keys_work_the_same_as_string_keys
    releases = [{tag_name: "v1.0.0", draft: false}]

    assert_equal({"latest" => "1.0.0"}, ReleaseChannels.channels(releases))
  end

  def test_a_release_with_only_a_symbol_tag_name_is_still_read
    release = {"draft" => false}
    release[:tag_name] = "v1.0.0"
    releases = [release]

    assert_equal({"latest" => "1.0.0"}, ReleaseChannels.channels(releases))
  end

  def test_a_release_with_no_tag_name_at_all_is_skipped_not_raised
    releases = [
      {"draft" => false},
      {"tag_name" => "v1.0.0", "draft" => false}
    ]

    assert_equal({"latest" => "1.0.0"}, ReleaseChannels.channels(releases))
  end

  def test_compare_returns_early_on_a_differing_major_version
    older = ReleaseChannels.parse("1.0.0")
    newer = ReleaseChannels.parse("2.0.0")

    assert_equal(-1, ReleaseChannels.compare(older, newer))
    assert_equal(1, ReleaseChannels.compare(newer, older))
  end

  # §11 precedence, exercised directly on compare so every prerelease-identifier branch
  # (numeric vs numeric, numeric vs alphanumeric either way round, alphanumeric vs
  # alphanumeric, and a shorter prerelease array) is provable without a channels() detour.
  def test_compare_numeric_prerelease_identifiers_by_value
    a = ReleaseChannels.parse("1.0.0-alpha.9")
    b = ReleaseChannels.parse("1.0.0-alpha.10")

    assert_equal(-1, ReleaseChannels.compare(a, b))
    assert_equal(1, ReleaseChannels.compare(b, a))
  end

  def test_compare_a_numeric_identifier_before_an_alphanumeric_one
    numeric = ReleaseChannels.parse("1.0.0-1")
    alpha = ReleaseChannels.parse("1.0.0-alpha")

    assert_equal(-1, ReleaseChannels.compare(numeric, alpha))
    assert_equal(1, ReleaseChannels.compare(alpha, numeric))
  end

  def test_compare_alphanumeric_prerelease_identifiers_lexically
    a = ReleaseChannels.parse("1.0.0-alpha")
    b = ReleaseChannels.parse("1.0.0-beta")

    assert_equal(-1, ReleaseChannels.compare(a, b))
    assert_equal(1, ReleaseChannels.compare(b, a))
  end

  def test_compare_equal_alphanumeric_identifiers_falls_through_to_the_next_one
    a = ReleaseChannels.parse("1.0.0-alpha.1")
    b = ReleaseChannels.parse("1.0.0-alpha.2")

    assert_equal(-1, ReleaseChannels.compare(a, b))
  end

  def test_compare_a_shorter_prerelease_sorts_before_a_longer_one_with_the_same_prefix
    shorter = ReleaseChannels.parse("1.0.0-alpha")
    longer = ReleaseChannels.parse("1.0.0-alpha.1")

    assert_equal(-1, ReleaseChannels.compare(shorter, longer))
    assert_equal(1, ReleaseChannels.compare(longer, shorter))
  end

  def test_compare_a_release_outranks_a_prerelease_of_the_same_version
    release = ReleaseChannels.parse("1.0.0")
    prerelease = ReleaseChannels.parse("1.0.0-alpha.1")

    assert_equal(1, ReleaseChannels.compare(release, prerelease))
    assert_equal(-1, ReleaseChannels.compare(prerelease, release))
  end

  def test_compare_two_plain_releases_with_no_prerelease_are_equal
    a = ReleaseChannels.parse("1.0.0")
    b = ReleaseChannels.parse("1.0.0")

    assert_equal(0, ReleaseChannels.compare(a, b))
  end

  def test_compare_identical_prerelease_identifiers_are_equal
    a = ReleaseChannels.parse("1.0.0-alpha.1")
    b = ReleaseChannels.parse("1.0.0-alpha.1")

    assert_equal(0, ReleaseChannels.compare(a, b))
  end
end
