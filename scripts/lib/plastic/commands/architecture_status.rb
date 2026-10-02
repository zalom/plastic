# frozen_string_literal: true

require_relative "../cli/command"
require "digest"
require "json"
require "shellwords"

module Plastic
  module Commands
    # Reads architecture facts without generating a snapshot.
    class ArchitectureStatus < CLI::Command
      reads :knowledge

      def call
        output.row("architecture", receipt)
        output.next_step(refresh_command, because: "an explicit refresh updates the architecture snapshot")
      end

      private

      def receipt
        compare_worktree(current_receipt)
      end

      def repository = scope.project_path

      def revision
        git("rev-parse", "HEAD").first.to_s.strip
      end

      def dirty
        !git("status", "--porcelain").first.to_s.strip.empty?
      end

      def binary_sha256
        path = `command -v enola`.strip
        File.file?(path) ? Digest::SHA256.file(path).hexdigest : nil
      end

      def archive_sha256 = nil

      def refresh_command
        project = parsed[:project]
        project ? "plastic architecture refresh --project #{Shellwords.shellescape(project)}" : "plastic architecture refresh"
      end

      def current_receipt
        Architecture::EnolaAdapter.new.snapshot(repository:, binary_sha256:, archive_sha256: nil, revision:, dirty:)
      end

      def compare_worktree(current)
        saved = stored_receipt
        return current unless current.fetch("state") == "fresh" && saved
        return current unless saved["worktree_hash"] && saved["revision"] == current["revision"] && saved["worktree_hash"] != worktree_hash

        current.merge("state" => "stale")
      end

      def stored_receipt
        row = graphs.databases.fetch(:knowledge).row("SELECT data FROM architecture_receipts WHERE provider = :provider AND origin_id = :origin",
          provider: "enola", origin: graphs.retrieval.origin_id)
        row ? JSON.parse(row.fetch("data")) : nil
      end

      def worktree_hash
        status = git("status", "--porcelain", "--untracked-files=all").first.to_s
        Digest::SHA256.hexdigest(status.lines.map { |line| dirty_file_digest(line) }.join)
      end

      def dirty_file_digest(line)
        path = line[3..].to_s.strip
        [line, File.file?(File.join(repository, path)) ? Digest::SHA256.file(File.join(repository, path)).hexdigest : "missing"].join("\0")
      end

      def git(*arguments)
        IO.popen(["git", "-C", repository, *arguments], err: [:child, :out], &:read).then { |result| [result, $?.success?] }
      rescue Errno::ENOENT
        ["", false]
      end
    end
  end
end
