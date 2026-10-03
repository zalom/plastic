# frozen_string_literal: true

require "json"
require "rubygems/version"
require_relative "https_fetch"
require_relative "release_files"

module InstallerRelease
  # Picks the newest release on a channel from the GitHub release list,
  # counting only releases that carry all three release files.
  module ReleaseFeed
    module_function

    def newest(releases, channel) = versions(releases).select { |version| on_channel?(version, channel) }.max_by { |version| order(version) }

    def versions(releases) = releases.select { |release| complete?(release) }.map { |release| release.fetch("tag_name").delete_prefix("v") }

    def newer?(candidate, current) = (order(candidate) <=> order(current)) == 1

    def order(version) = Gem::Version.new(version)

    def complete?(release) = (ReleaseFiles::NAMES - release.fetch("assets").map { |asset| asset["name"] }).empty?

    def on_channel?(version, channel) = Manifest.identity(version).fetch("channel") == channel
  end

  # Where releases come from: GitHub, or a local directory in development.
  module ReleaseSource
    def self.for(directory) = directory ? LocalSource.new(directory) : GithubSource.new
  end

  # The official releases, read from the GitHub API and downloaded over HTTPS.
  class GithubSource
    API = "https://api.github.com/repos/zalom/plastic/releases?per_page=50"
    DOWNLOAD = "https://github.com/zalom/plastic/releases/download/v%<version>s/%<name>s"

    def initialize(fetch: HttpsFetch.new)
      @fetch = fetch
    end

    def newest(channel) = ReleaseFeed.newest(JSON.parse(fetch.read(API)), channel)

    def files(version, directory)
      ReleaseFiles::NAMES.each { |name| fetch.download(format(DOWNLOAD, version: version, name: name), File.join(directory, name)) }
      ReleaseFiles.new(directory)
    end

    def trusted? = true

    def notices = []

    private

    attr_reader :fetch
  end

  # A directory holding one release's three files, for development only.
  class LocalSource
    DEVELOPMENT = "development mode: reading releases from %s; this claims no release trust"

    def initialize(directory)
      @directory = directory
      @files = ReleaseFiles.new(directory)
    end

    def newest(_channel) = files.manifest.dig("release", "version")

    def files(_version = nil, _directory = nil) = @files

    def trusted? = false

    def notices = [format(DEVELOPMENT, @directory)]
  end
end
