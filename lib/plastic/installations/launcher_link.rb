# frozen_string_literal: true

module Plastic
  module Installations
    # The launcher in the bin directory. Plastic owns it while it is missing,
    # a link into the share, or a link to the launcher of an earlier release;
    # a launcher the user wrote, or a link to another program, is not Plastic's
    # and stays as it is.
    class LauncherLink
      attr_reader :path

      def initialize(path, share, retired: [])
        @path = path
        @share = share
        @retired = retired
      end

      def ours?
        return !File.exist?(path) unless File.symlink?(path)

        into_share? || retired.include?(target)
      end

      def linked? = File.symlink?(path) && into_share?

      private

      attr_reader :share, :retired

      def target = File.expand_path(File.readlink(path), File.dirname(path))

      def into_share? = target.start_with?("#{share}/")
    end
  end
end
