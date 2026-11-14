# frozen_string_literal: true

require "fileutils"

module Plastic
  module Installations
    # Copies each skills/NAME folder of a package to PLASTIC-NAME under the
    # skills root of one agent. A top-level markdown file whose name starts
    # with an underscore is a fragment every skill reads, so it lands in the
    # Plastic home instead. `exclude` leaves named skills out.
    class SkillCopy
      def initialize(package_root, plastic_home)
        @source = File.join(package_root, "skills")
        @plastic_home = plastic_home
      end

      def call(skills_root, exclude: [])
        return [] unless File.directory?(@source)

        FileUtils.mkdir_p(skills_root)
        entries(exclude).flat_map { |entry| copy_entry(entry, skills_root) }
      end

      # The fragment files a prune may reach under the Plastic home.
      def fragments
        return [] unless File.directory?(@source)

        Dir.children(@source).select { |entry| fragment?(entry) }.map { |entry| File.join(@plastic_home, entry) }
      end

      private

      def entries(exclude) = Dir.children(@source).reject { |entry| entry.start_with?(".") || exclude.include?(entry) }

      def fragment?(entry) = entry.start_with?("_") && entry.end_with?(".md")

      def copy_entry(entry, skills_root)
        path = File.join(@source, entry)
        return copy_folder(path, File.join(skills_root, "plastic-#{entry}")) if File.directory?(path)

        fragment?(entry) ? [copy_fragment(path, entry)] : []
      end

      def copy_fragment(path, entry)
        FileUtils.mkdir_p(@plastic_home)
        copied = File.join(@plastic_home, entry)
        FileUtils.cp(path, copied)
        copied
      end

      def copy_folder(source, target)
        FileUtils.mkdir_p(target)
        visible(source).flat_map do |entry|
          path = File.join(source, entry)
          copied = File.join(target, entry)
          next copy_folder(path, copied) if File.directory?(path)

          FileUtils.cp(path, copied)
          [copied]
        end
      end

      def visible(folder) = Dir.children(folder).reject { |entry| entry.start_with?(".") }
    end
  end
end
