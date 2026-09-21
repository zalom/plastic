# frozen_string_literal: true

require_relative "../command"
require_relative "version"
require_relative "../../backup"

module Plastic
  class CLI
    module Commands
      class Backup < Command
        USAGE_LINE = "plastic backup [--list] [--json]"

        def call
          options[:list] ? list : write
        rescue Plastic::Backup::Missing => e
          @output.next_step("plastic sync", because: "a backup copies the three databases, and sync builds them")
          raise Failure, "no #{e.message} at #{scope.plastic_home}; run plastic sync"
        rescue Sqlite::Error => e
          raise Failure, e.message
        end

        private

        def switches(parser)
          parser.on("--list") { options[:list] = true }
        end

        def write
          version = Version.new([], out: nil, err: nil, env: @env).found.last
          @output.row("archive", Plastic::Backup.call(scope.plastic_home, version: version))
          @output.next_step("plastic backup --list", because: "to restore, unpack the archive into an empty ~/.plastic and run plastic checkout")
        end

        def list
          archives = Plastic::Backup.list(scope.plastic_home)
          archives.each { |path| @output.row(File.basename(path), "#{File.size(path)} bytes  #{File.mtime(path).strftime("%Y-%m-%d %H:%M")}") }
          @output.row("result", "no backup yet") if archives.empty?
          @output.next_step("plastic backup", because: "copying backups/ off this machine is your choice; Plastic sends nothing")
        end
      end
    end
  end
end
