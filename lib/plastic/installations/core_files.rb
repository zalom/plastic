# frozen_string_literal: true

module Plastic
  module Installations
    # The files of the package that reach the Plastic home: two hand-named
    # files, the hook launchers, the kernel command tree and the help
    # chapters. The last three are found on disk, so a new file in them ships
    # with no change here. The status line script ships only while the
    # setting `statusline` is on. The result maps each package path to its
    # path in the home, which is the same path.
    class CoreFiles
      HAND = %w[PLASTIC.md exe/plastic].freeze
      STATUS_LINE = "hooks/statusline"

      def initialize(package_root, status_line:)
        @root = package_root
        @status_line = status_line
      end

      def call = [*HAND, *hooks, *kernel, *help].to_h { |path| [path, path] }

      private

      def hooks = found("hooks/*").select { |path| File.file?(File.join(@root, path)) && (@status_line || path != STATUS_LINE) }

      def kernel = [*found("lib/plastic/**/*.rb"), "lib/plastic.rb"]

      def help = found("docs/help/*.md")

      def found(pattern) = Dir.glob(File.join(@root, pattern)).map { |path| path.delete_prefix("#{@root}/") }.sort
    end
  end
end
