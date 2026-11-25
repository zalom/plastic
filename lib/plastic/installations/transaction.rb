# frozen_string_literal: true

require_relative "prune"
require_relative "snapshot"

module Plastic
  module Installations
    # One agent's install as a unit. It refuses an agent whose folder is
    # missing, prunes what the install dropped, and when the files it wrote
    # fail their check, it puts the prior files back, or removes a partial
    # first install.
    class Transaction
      def initialize(home, record, roots, verified: -> { record.manifest.verified? })
        @home = home
        @record = record
        @roots = roots
        @verified = verified
      end

      def call(&install)
        return refusal unless @record.present?

        from = @record.version
        snapshot = capture_snapshot
        result = settle(sync(&install), snapshot)
        result.merge(from_version: from, to_version: version_after)
      end

      private

      def refusal
        name = @record.name
        { agent: name, success: false, reason: "#{@record.presence_dir} not found, #{name} not installed?" }
      end

      def capture_snapshot
        manifest = @record.manifest
        return Snapshot::NONE if manifest.empty?

        Snapshot.new(File.join(@home, "backups", @record.key), manifest).capture
      end

      def sync
        former = @record.former_files
        result = yield
        pruned = result[:success] ? prune(former - @record.manifest.files) : 0
        @record.retire_legacy
        pruned.positive? ? result.merge(pruned:) : result
      end

      def settle(result, snapshot)
        return result if !result[:success] || @verified.call

        result.merge(success: false, reason: undo(snapshot))
      end

      def undo(snapshot)
        return "verify failed - restored prior snapshot" if snapshot.restore

        prune(@record.manifest.files)
        "verify failed - partial install pruned"
      end

      def version_after = @record.version

      def prune(stale) = Prune.new(home: @home, roots: @roots).call(stale)
    end
  end
end
