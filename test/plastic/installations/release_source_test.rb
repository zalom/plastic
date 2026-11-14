# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "release_fixture"
require "json"
require "plastic/installations/release_source"

class ReleaseSourceTest < Plastic::TestCase
  include ReleaseFixture

  ASSETS = %w[plastic.tgz plastic.tgz.sha256 plastic.manifest.json].map { |name| { "name" => name } }.freeze
  RELEASES = [
    { "tag_name" => "v2.1.0-alpha.2", "prerelease" => true, "assets" => ASSETS },
    { "tag_name" => "v2.0.4", "prerelease" => false, "assets" => ASSETS.first(1) },
    { "tag_name" => "v2.0.3-beta.1", "prerelease" => true, "assets" => ASSETS },
    { "tag_name" => "v2.0.0-alpha.27", "prerelease" => false, "assets" => ASSETS },
    { "tag_name" => "v2.0.3", "prerelease" => false, "assets" => ASSETS }
  ].freeze

  # Serves the release list and the files of one release directory.
  class FakeFetch
    attr_reader :downloaded

    def initialize(releases, directory)
      @releases = releases
      @directory = directory
      @downloaded = []
    end

    def read(url)
      raise "unexpected #{url}" unless url == Plastic::Installations::GithubSource::API

      JSON.generate(@releases)
    end

    def download(url, path)
      @downloaded << url
      FileUtils.cp(File.join(@directory, File.basename(url)), path)
    end
  end

  def test_picks_the_newest_complete_release_on_each_channel
    newest = %w[latest alpha beta].map { |channel| Plastic::Installations::ReleaseFeed.newest(RELEASES, channel) }

    assert_equal %w[2.0.3 2.1.0-alpha.2 2.0.3-beta.1], newest
    assert_nil Plastic::Installations::ReleaseFeed.newest([], "latest")
  end

  def test_orders_versions_as_versions
    feed = Plastic::Installations::ReleaseFeed

    assert feed.newer?("2.0.3", "2.0.3-alpha.5")
    assert feed.newer?("2.0.10", "2.0.9")
    refute feed.newer?("2.0.3-beta.1", "2.0.3")
  end

  def test_a_version_names_its_channel
    channels = %w[2.0.3 2.1.0-alpha.4 2.0.3-beta.1].map { |version| Plastic::Installations::ReleaseFeed.channel_of(version) }

    assert_equal %w[latest alpha beta], channels
  end

  def test_github_reads_the_newest_release_and_downloads_its_three_files
    fetch = FakeFetch.new(RELEASES, release_files)
    source = Plastic::Installations::GithubSource.new(fetch: fetch)
    target = FileUtils.mkdir_p(File.join(@home, "download")).first

    assert_equal "2.0.3", source.newest("latest")
    assert source.files("2.0.3", target).verify
    assert_equal "https://github.com/zalom/plastic/releases/download/v2.0.3/plastic.tgz", fetch.downloaded.first
  end

  def test_github_gives_no_notice
    assert_empty Plastic::Installations::GithubSource.new(fetch: nil).notices
  end

  def test_a_local_directory_offers_its_own_release_and_claims_no_trust
    directory = release_files
    source = Plastic::Installations::ReleaseSource.for(directory)
    target = FileUtils.mkdir_p(File.join(@home, "download")).first

    assert_equal "2.0.3", source.newest("alpha")
    assert_equal File.join(target, "plastic.tgz"), source.files("2.0.3", target).archive
    assert_equal ["development mode: reading releases from #{directory}; this claims no release trust"], source.notices
  end

  def test_with_no_local_directory_the_source_is_github
    assert_instance_of Plastic::Installations::GithubSource, Plastic::Installations::ReleaseSource.for(nil)
  end
end
