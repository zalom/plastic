# frozen_string_literal: true

require_relative "../../test_helper"
require "plastic/installations/snapshot"

class SnapshotTest < Plastic::TestCase
  def test_the_absent_snapshot_restores_nothing
    refute Plastic::Installations::Snapshot::NONE.restore
  end
end
