# frozen_string_literal: true

require "digest"

module Plastic
  module Architecture
    # Captures source identity without generating or changing an architecture snapshot.
    class SourceState
      def initialize(repository)
        @repository = repository
      end

      def source
        EnolaSnapshot::Source.new(repository: @repository, revision:, dirty:)
      end

      def identity
        EnolaProvenance::Identity.new(binary_digest:, archive_digest: nil)
      end

      def worktree_hash
        Digest::SHA256.hexdigest(status_lines.map { |line| file_digest(line) }.join)
      end

      private

      def revision = git("rev-parse", "HEAD").first.to_s.strip

      def dirty = !git("status", "--porcelain").first.to_s.strip.empty?

      def binary_digest
        path = `command -v enola`.strip
        File.file?(path) ? Digest::SHA256.file(path).hexdigest : nil
      end

      def status_lines = git("status", "--porcelain", "--untracked-files=all").first.to_s.lines

      def file_digest(line)
        path = line[3..].to_s.strip
        target = File.join(@repository, path)
        [line, File.file?(target) ? Digest::SHA256.file(target).hexdigest : "missing"].join("\0")
      end

      def git(*arguments)
        IO.popen(["git", "-C", @repository, *arguments], err: [:child, :out], &:read).then { |result| [result, $?.success?] }
      rescue Errno::ENOENT
        ["", false]
      end
    end

    # Marks a saved receipt stale when the current worktree changed after refresh.
    class ReceiptFreshness
      def initialize(current:, saved:, worktree_hash:)
        @current = current
        @saved = saved
        @worktree_hash = worktree_hash
      end

      def receipt
        return @current unless same_revision? && changed_worktree?

        @current.merge("state" => "stale")
      end

      private

      def same_revision? = @current.fetch("state") == "fresh" && @saved && @saved["revision"] == @current["revision"]

      def changed_worktree?
        saved_hash = @saved["worktree_hash"]
        saved_hash && saved_hash != @worktree_hash
      end
    end
  end
end
