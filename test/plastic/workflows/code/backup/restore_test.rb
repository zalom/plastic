# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/workflows/code/backup/restore"

class RestoreBackupOutcomeTest < Plastic::TestCase
  def outcome = Plastic::Workflows::Code::Backup::Restore.outcomes.first

  def test_the_outcome_offers_no_sync_command
    assert_nil outcome.offers
  end

  def test_the_outcome_asks_the_person_whether_to_sync_up_or_down
    assert_includes outcome.because, "ask the person whether to run plastic sync down"
    assert_includes outcome.because, "plastic sync up"
  end
end
