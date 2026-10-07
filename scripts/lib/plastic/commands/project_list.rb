# frozen_string_literal: true

require_relative "../cli/command"

module Plastic
  module Commands
    # Lists the projects of projects.yml, each with its path, and marks the
    # ones whose store folder is missing. It writes nothing.
    class ProjectList < CLI::Command
      NO_STORE = " (no store)"

      def call
        projects = scope.projects
        projects.sort.each { |slug, path| output.raw("#{slug}: #{path}#{NO_STORE unless store?(slug)}") }
        return output.next_step("plastic project new SLUG PATH", because: "no project is registered yet") if projects.empty?

        output.next_step("plastic status", because: "the projects are listed")
      end

      private

      def store?(slug) = File.directory?(File.join(scope.plastic_home, "stores", slug))
    end
  end
end
