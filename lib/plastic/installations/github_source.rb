# frozen_string_literal: true

require "json"
require_relative "https_fetch"
require_relative "release_feed"
require_relative "release_files"

module Plastic
  module Installations
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

      def notices = []

      private

      attr_reader :fetch
    end
  end
end
