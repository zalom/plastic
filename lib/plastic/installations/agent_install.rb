# frozen_string_literal: true

require "fileutils"
require_relative "agent_record"
require_relative "package"
require_relative "role_files"
require_relative "skill_copy"

module Plastic
  module Installations
    # One agent's install from a package. A subclass names what it copies and
    # what it merges into the files of the person; this class writes the
    # version and the manifest, and returns the result of the install.
    class AgentInstall
      def initialize(package, record)
        @package = package
        @record = record
      end

      def call
        FileUtils.mkdir_p(record.dir)
        files = copy << record.write_version(package.version)
        extra = integrate
        seal(files)
        outcome(files).merge(extra)
      end

      private

      attr_reader :package, :record

      def seal(files) = record.manifest.write(files, package.clock.now)

      def outcome(files) = { agent: record.name, success: true, files: files.size }

      def integrate = {}

      def skills(exclude: []) = SkillCopy.new(package.root, package.home).call(File.join(record.root, "skills"), exclude:)

      def role_files
        choices = package.choices
        RoleFiles.new(package.root, models: choices.models, efforts: choices.efforts, skip: choices.skipped_roles, workers: choices.max_workers).call(File.join(record.root, "agents"))
      end

      def advisor_exclusions = package.choices.advisor? ? [] : ["agent-advisor"]
    end
  end
end
