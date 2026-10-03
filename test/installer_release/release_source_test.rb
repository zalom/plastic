# frozen_string_literal: true

require "json"
require_relative "release_helper"

class InstallerReleaseSourceTest < Minitest::Test
  include ReleaseHelper

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
      raise "unexpected #{url}" unless url == InstallerRelease::GithubSource::API

      JSON.generate(@releases)
    end

    def download(url, path)
      @downloaded << url
      FileUtils.cp(File.join(@directory, File.basename(url)), path)
    end
  end

  def test_picks_the_newest_complete_release_on_each_channel
    assert_equal "2.0.3", InstallerRelease::ReleaseFeed.newest(RELEASES, "latest")
    assert_equal "2.1.0-alpha.2", InstallerRelease::ReleaseFeed.newest(RELEASES, "alpha")
    assert_equal "2.0.3-beta.1", InstallerRelease::ReleaseFeed.newest(RELEASES, "beta")
    assert_nil InstallerRelease::ReleaseFeed.newest([], "latest")
  end

  def test_github_reads_the_newest_release_and_downloads_its_three_files
    fetch = FakeFetch.new(RELEASES, release_files)
    source = InstallerRelease::GithubSource.new(fetch: fetch)
    target = FileUtils.mkdir_p(File.join(@root, "download")).first

    assert_equal "2.0.3", source.newest("latest")
    assert source.files("2.0.3", target).verify
    assert_equal "https://github.com/zalom/plastic/releases/download/v2.0.3/plastic.tgz", fetch.downloaded.first
    assert source.trusted?
  end

  def test_a_local_directory_offers_its_own_release_and_claims_no_trust
    directory = release_files
    source = InstallerRelease::ReleaseSource.for(directory)

    assert_equal "2.0.3", source.newest("alpha")
    assert_equal File.join(directory, "plastic.tgz"), source.files("2.0.3", @root).archive
    refute source.trusted?
  end

  def test_with_no_local_directory_the_source_is_github
    assert_instance_of InstallerRelease::GithubSource, InstallerRelease::ReleaseSource.for(nil)
  end
end
