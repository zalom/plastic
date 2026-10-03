# frozen_string_literal: true

require "json"
require_relative "https_fetch"
require_relative "release_files"

module InstallerRelease
  # Picks the newest release on a channel from the GitHub release list,
  # counting only releases that carry all three release files.
  module ReleaseFeed
    module_function

    def newest(releases, channel)
      versions = releases.select { |release| complete?(release) }.map { |release| release.fetch("tag_name").delete_prefix("v") }
      versions.select { |version| on_channel?(version, channel) }.max_by { |version| version.scan(/\d+/).map(&:to_i) }
    end

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

    private

    attr_reader :fetch
  end

  # A directory holding one release's three files, for development only.
  class LocalSource
    def initialize(directory)
      @files = ReleaseFiles.new(directory)
    end

    def newest(_channel) = files.manifest.dig("release", "version")

    def files(_version = nil, _directory = nil) = @files

    def trusted? = false
  end
end
