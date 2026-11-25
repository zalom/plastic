# frozen_string_literal: true

require_relative "github_source"
require_relative "local_source"

module Plastic
  module Installations
    # Where releases come from: GitHub, or a local directory in development.
    module ReleaseSource
      def self.for(directory) = directory ? LocalSource.new(directory) : GithubSource.new
    end
  end
end
