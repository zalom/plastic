# frozen_string_literal: true

require_relative "../graph/backup/due"

module Plastic
  class Routine < CLI::Command
    # `backs_up_first` in a routine's class body makes the call take a backup
    # of its store first, when the newest backup is older than twelve hours.
    # A dry run takes none. The backup never stops the call.
    module BackupFirst
      # The class-body word.
      module Declaration
        def backs_up_first = (@backs_up_first = true)

        def backs_up_first? = @backs_up_first == true
      end

      private

      def back_up_first
        return unless self.class.backs_up_first? && !parsed[:dry_run]

        result = Graph::Backup::Due.new(home: scope.plastic_home, slug: backup_slug, now: environment.now).call(words)
        say_failure(result) if result.status == :failed
      end

      def say_failure(result) = environment.err.puts("backup: #{backup_slug} was not backed up (#{result.reason}); the call goes on")

      def backup_slug = parsed[:store] || scope.slug
    end
  end
end
