# frozen_string_literal: true

require "fileutils"
require_relative "manifest"

module Plastic
  module Installations
    # What one agent keeps of an install: the folder <agent>/plastic holding
    # the version and the manifest of the files the install wrote. An agent
    # is installed when the record has a version, and registered when a file
    # its manifest lists exists.
    class AgentRecord
      attr_reader :config

      def initialize(config)
        @config = config
      end

      def key = config[:key]

      def name = config[:name]

      def root = config[:dir]

      def dir = File.join(root, "plastic")

      def manifest = Manifest.new(File.join(dir, "manifest.json"))

      def legacy = Manifest.new(File.join(root, "plastic-manifest.json"))

      def version_path = File.join(dir, "VERSION")

      def version = installed? ? File.read(version_path).strip : nil

      def installed? = File.exist?(version_path)

      def registered? = manifest.files.any? { |path| File.exist?(path) }

      # Codex keeps its own folder apart from the shared skills folder, so its
      # presence is checked there.
      def presence_dir = config[:home_dir] || root

      def present? = File.directory?(presence_dir)

      def former_files = manifest.files | legacy.files

      def retire_legacy = FileUtils.rm_f(legacy.path)

      def roots(fragments) = [root, config[:home_dir], *fragments].compact

      def write_version(version)
        FileUtils.mkdir_p(dir)
        File.write(version_path, "#{version}\n")
        version_path
      end
    end
  end
end
